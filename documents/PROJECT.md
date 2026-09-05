# Signalarm (開発コードネーム: Alarmify)

外部サービスからの HTTP リクエスト (Webhook / REST API) を契機に、ユーザーが操作していない iPhone の AlarmKit アラームを登録・更新する iOS アプリ。「Anything → Signalarm API → iPhone → AlarmKit」。

- 企画の起点: https://github.com/bannzai/IdeaMemo/issues/194 (先行事例 PushWard / Wakey / Pealo / Alarm Friend の調査と、実現方式の検証計画)
- 製品名は「Signalarm」(2026-09-04 決定。App Store Connect のアプリレコードはこの名前で作成済み、app id 6808548984。候補の確認結果: https://github.com/bannzai/Alarmify/issues/14#issuecomment-5537519985 )。「Alarmify」は開発コードネームで、App Store に「Alarmify™」(Spotify 連携の目覚まし) が存在し類似名も複数あるため製品名には使わない。利用者の目に触れる名称 (ストア表示名・LP・法務ドキュメント・アプリ内表示・push の通知タイトル・アラームの既定タイトル) は Signalarm、コード・リポジトリ名・bundle id (`com.bannzai.Alarmify`)・App Group・ターゲット名・スキーム名・profile 名・GitHub Pages のパス (`bannzai.github.io/Alarmify/`) はコードネームのまま使う

## コンセプト

通知ではなく「本物のアラーム」を、任意の外部イベントから鳴らす。

- AlarmKit (iOS 26+) のアラームはサイレントモード・集中モードを突破し、ロック画面に表示され、アプリを閉じていても鳴る。push 通知にはできないことが差別化の核
- 競合調査 (2026-09-02) の結論: 「汎用 Webhook / API × AlarmKit の本物のアラーム」を組み合わせた既存アプリは見つからなかった。AlarmKit 採用アプリ (Beacon、Pealo) はカレンダー連携専用、汎用 Webhook アプリ (PushWard、Echobell、AssistantPager、Pushcut、Pushover) は通知・Live Activity・自動音声電話で代替している
- 一言説明: 「Webhook を iPhone の本物のアラームにする」

## ターゲット

- オンコールのエンジニア (CI・監視・デプロイ完了をアラームで受けたい)
- Home Assistant 等のホームオートメーション利用者 (侵入検知・センサーのイベントで iPhone を鳴らしたい。Home Assistant コミュニティに「サーバー → iPhone の実アラーム」の要望スレッドが複数ある)
- カレンダー・cron 等のサーバー側の予定でアプリを開かずに起こされたい人

## コア体験

1. **セットアップ**: アプリでアラームの権限を許可し、API トークンを発行する (アカウントは Firebase Auth の匿名認証で自動作成し、Firebase Auth の keychain 永続化で同じ端末の再インストールを跨ぐ。端末の買い替え時はトークンを発行し直す運用とし、Sign in with Apple による端末間の引き継ぎは MVP に含めない。必要になった時点で検討する)
2. **外部から呼ぶ**: 任意のサービスが `POST /v1/alarms` に `fire_at` と `title` を送る。バックエンドがユーザーの端末へ push を配送し、iPhone 側が AlarmKit にアラームを登録する。ユーザーは何もしない
3. **鳴る**: 指定時刻に AlarmKit のアラームが鳴る。取り消し・再スケジュールも API から行える
4. **履歴** (Pro): どのサービスからいつアラームが登録・発火したかをアプリで確認できる

## 技術方針

- iOS 26+ 専用。SwiftUI + AlarmKit。Xcode プロジェクトは直接管理する ([ADR 0002](adr/0002-manage-xcode-project-directly.md))
- バックエンドは Firebase (Cloud Functions gen2 + Firestore + Firebase Auth + FCM + App Check)。決定の経緯と代替案 (Cloudflare Workers 等) の比較は [ADR 0001](adr/0001-firebase-backend.md)。GCP プロジェクトは `alarmify-prod` (asia-northeast1)
- サーバー → iPhone の配送経路は 3 方式を順に実機検証して決める (経緯と判断基準: https://github.com/bannzai/IdeaMemo/issues/194 )。iOS 側は経路に関わらず `AlarmRequest` → `AlarmKitScheduler.apply` の 1 経路に正規化する (`.claude/rules/ios-alarmkit-constraints.md`)
  1. Notification Service Extension (visible push + `mutable-content: 1`)
  2. Silent / Background Push (`content-available: 1`)
  3. Live Activity / ActivityKit Remote Push (PushWard が最も近い先行事例)
- 2026-09-02 の雛形検証 (simulator iOS 26.5): app 本体からの AlarmKit 権限取得・登録は動作。`xcrun simctl push` の visible push は届いたが Notification Service Extension のプロセスは起動しなかった (ログに extension の記録なし)。Extension 経路の検証は実機 + 実 APNs で行う
- 課金は RevenueCat。Analytics / Crashlytics は MVP では導入しない
- 参考実装: bannzai/mementomorning (AlarmKit の基盤・規約の取り込み元)、bannzai/Pilll (AlarmKit 利用)

## 課金設計 (Freemium + サブスクリプション)

競合の価格帯: Pushover $4.99 買い切り、Pushcut Pro 年 $17.99、PushWard Pro 年 $23.99 / Lifetime $99、Echobell 年 ¥3,000。AlarmKit 採用の Beacon は年 €35 で Hacker News に反発され年 $15 へ値下げした (個人向けツールの支払い上限の実測値)。

| 層 | 内容 | 狙い |
| --- | --- | --- |
| 無料 | API トークン 1 つ・月 20 回までのアラーム登録・アプリ内からのテストアラーム | 「Webhook で本物のアラームが鳴る」体験を完全に試せる線 |
| Pro (年 $14.99 目安。月額は $1.99〜2.99 目安) | 複数トークン (サービス別)・無制限の登録・アラーム履歴・複数端末への配送 | サーバー側で価値を出す機能を Pro に寄せ、サブスクに値する理由を明確にする |

価格の確定と RevenueCat の商品設定は公開前チェックリストで扱う。

## 競合の実測 (2026-09-02、iTunes Search API)

| アプリ | 価格 | US 評価 | AlarmKit | 備考 |
| --- | --- | --- | --- | --- |
| PushWard | Free / Pro 年 $23.99 / Lifetime $99 | 新規 (0 件) | × (Live Activity) | Webhook → Live Activity。連携 20 以上 |
| Echobell | Free / 年 ¥3,000 | 4.5 (2 件) | × (自動音声電話でサイレント突破) | Grafana / IFTTT / Home Assistant 対応 |
| Pushcut | Free / Pro 年 $17.99 | 4.40 (536 件) | × | Webhook → ショートカット起動 |
| Pushover | $4.99 買い切り | 4.84 (3,583 件) | × | 開発者に人気の通知 API |
| Beacon: Calendar Alarms | Free / 年 $15 | 4.24 (17 件) | ○ | カレンダー専用 |
| Pealo | Free + サブスク | 新規 | ○ | カレンダー専用 |
| PagerDuty 等のオンコール SaaS | 月 $21〜41 / ユーザー | 4.83 (5,229 件) | × (電話発信) | 企業向け。個人には過剰 |

需要シグナルの詳細 (Hacker News の Beacon スレッド、Home Assistant コミュニティの要望) と調査の全文は https://github.com/bannzai/IdeaMemo/issues/194 のコメントに記録している。
