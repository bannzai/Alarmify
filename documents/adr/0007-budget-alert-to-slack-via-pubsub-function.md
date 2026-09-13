# 0007. 予算アラートは Pub/Sub トピック + Functions で Slack へ転送する

## Status
Accepted (2026-09-14)

## Context
Cloud Billing の予算 `budget-alarmify-prod` (月 ¥10,000、50 / 90 / 100%) の通知先は Cloud Monitoring の email チャンネル 1 つだけで、Slack `#alarmify-notification` には届かない (#62 の確認結果)。Cloud Billing の予算が `monitoringNotificationChannels` として受け付けるのは email 型のチャンネルだけで、error-log-spike アラートが使っている Slack 型のチャンネルは紐づけられない。予算からプログラムで通知を受ける経路は Pub/Sub トピックへの publish だけ ( https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications ) で、トピックを購読して Slack へ投稿する仕組みが要る (#73)。

Pub/Sub から Slack への転送先には次の選択肢があった。

1. `firebase/functions/` に Pub/Sub トリガーの関数を 1 つ足し、slack-notification-setup skill の通知 bot の bot token で `chat.postMessage` する
2. Cloud Run の別サービス、または Workflows / Eventarc から Slack の Incoming Webhook へ直接送る
3. Pub/Sub の push サブスクリプションから Slack の Incoming Webhook へ直接 POST する

2 と 3 は Incoming Webhook URL が要る。Slack の Incoming Webhook は bot token だけでは発行できず、App 管理画面での人の操作が要る (slack-notification-setup skill「Incoming Webhook が必要な場合」)。また予算通知は閾値の超過に関係なく 1 日に複数回届き、超過後はどの通知にも同じ閾値が載るため、そのまま転送すると閾値を超えた月は毎日数回同じ投稿が続く。転送の途中で「新しく超えた閾値だけを投稿する」判定と、その記録を置く場所が要り、3 では実現できない。

1 は既存のデプロイ経路 (`firebase deploy --only functions`)・Secret Manager (`defineSecret`)・Firestore (`.claude/rules/firestore-db-rules.md` のスキーマ管理)・エミュレータのテストをそのまま使え、bot token は Cloud Monitoring の Slack チャンネルにも使っている既存のものを流用できる。Functions が 1 つ増えるが、予算通知は 1 日数回のため Cloud Run の費用は誤差で、最小インスタンス 0 のままアイドル課金も無い。

## Decision
方式 1 を採る。Functions `budgetAlertToSlack` (`firebase/functions/src/index.ts`) が Pub/Sub トピック `budget-alarmify-prod` を購読し、次の規則で Slack `#alarmify-notification` へ投稿する (判定の本体は `firebase/functions/src/lib/budgetAlert.ts`)。

- **投稿する条件**: 通知本文の `alertThresholdExceeded` (実績の閾値) が載っている時だけ。予測 (`forecastThresholdExceeded`) は予算に予測ルールが無いため使わない
- **重複の抑止**: 集計期間 (`costIntervalStart`) ごとに投稿済みの最大閾値を Firestore `budgetNotifications/{budgetId}` に覚え、閾値が上がった時だけ投稿する。月が変わると記録を捨てる。記録は Slack への投稿が成功した後に書き、失敗した通知は次の通知 (数時間後) で投稿し直す (Pub/Sub トリガーの再試行は使わない)
- **認証**: Slack の bot token は Secret `SLACK_BOT_TOKEN`。設定手順は `documents/budget-alert-slack.md`
- **既存の email 通知**: そのまま残す。Pub/Sub トピックは email チャンネルと併存する
- **投稿先**: `#alarmify-notification` をコードの定数にする (slack-notification-setup skill の規約「サービス名-notification」で決まる固定の宛先で、環境ごとに変える値ではない)

## Consequences

**良い点:**
- 予算の閾値超過が email と同時に Slack にも届き、error-log-spike と同じチャンネルで見られる
- 閾値の判定と重複の抑止が純粋な関数と Firestore の 1 ドキュメントで完結し、エミュレータのテストで冪等性まで検証できる
- 新しい外部サービス・API キーを増やさない (Slack bot と Firebase の既存の資格情報だけ)

**悪い点 / 引き受けるリスク:**
- Secret `SLACK_BOT_TOKEN` が Secret Manager に無いと `firebase deploy` が Functions 全体で止まる (`REVENUECAT_WEBHOOK_AUTHORIZATION` と同じ)。bot token を作り直した時は Secret の更新と再デプロイが要る
- Pub/Sub トリガーの関数を初めて作る時に firebase-tools がトピックの作成とサービスエージェントへのロール付与を行うため、それらの権限が無い GitHub Actions のデプロイ用サービスアカウントでは初回の作成ができない。初回だけオーナーのアカウントでローカルからデプロイする (以後の更新は CI でよい)
- 予算からトピックへの通知は Google 側の配送で、届く時刻は数時間の幅がある。閾値超過から Slack への投稿までの遅れは email 通知と同程度
- 同じ予算の通知が同時に 2 件届くと二重投稿になり得る (通知の間隔は数時間あるため競合の制御は持たない)
- 予算通知の本文の形式は Google のドキュメントに依存する。形式が変わると `invalid` としてログに残るだけで投稿されない
