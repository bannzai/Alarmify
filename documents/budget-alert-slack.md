# 予算アラートを Slack へ流す設定手順 (Pub/Sub + Functions)

Cloud Billing の予算 `budget-alarmify-prod` (月 ¥10,000、50 / 90 / 100%) の閾値通知を Slack `#alarmify-notification` に届ける構成と、本番で有効にするまでの手順。方式の選定は [ADR 0007](adr/0007-budget-alert-to-slack-via-pubsub-function.md)、起票元は https://github.com/bannzai/Alarmify/issues/73 。

Cloud Billing の予算が Monitoring の通知チャンネルとして受け付けるのは email 型だけで、Slack 型のチャンネルは紐づけられない。予算に Pub/Sub トピックを紐づけると、閾値の超過に関係なく 1 日に複数回、予算の現在の状態がメッセージとして届く ( https://docs.cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications )。それを Functions `budgetAlertToSlack` が受け、閾値を新しく超えた時だけ Slack へ投稿する。

| 項目 | 値 |
| --- | --- |
| 予算 | `billingAccounts/013124-184724-31547F/budgets/655b729c-8d1e-4e9f-a458-dbce538d6c6d` (displayName `budget-alarmify-prod`) |
| Pub/Sub トピック | `projects/alarmify-prod/topics/budget-alarmify-prod` (`BUDGET_PUBSUB_TOPIC`) |
| 関数 | `budgetAlertToSlack` (`firebase/functions/src/index.ts`。転送の本体は `firebase/functions/src/lib/budgetAlert.ts`) |
| 投稿先 | Slack `#alarmify-notification` (`BUDGET_SLACK_CHANNEL`。slack-notification-setup skill が作った通知チャンネルで、error-log-spike アラートと同じ) |
| 投稿に使う token | Secret `SLACK_BOT_TOKEN` (slack-notification-setup skill の通知 bot の bot token。`chat:write` スコープ) |
| 投稿済みの記録 | Firestore `budgetNotifications/{budgetId}` (`firebase/functions/src/schema/budgetNotification.ts`) |

既存の email 通知 (Monitoring の email チャンネル) はそのまま残す。Pub/Sub トピックの紐づけは email チャンネルの設定と併存する。

## 投稿の規則

- 予算通知の本文 (`alertThresholdExceeded`) に閾値が載っている時だけ投稿する。閾値を超えていない通常の状態報告 (1 日数回) は何もしない
- 超過後はどの通知にも同じ閾値が載るため、集計期間 (`costIntervalStart`。月次予算では月初) ごとに投稿済みの最大閾値を `budgetNotifications/{budgetId}` に覚え、閾値が上がった時 (50% → 90% → 100%) だけ投稿する。月が変わると記録を捨てて 50% から投稿し直す
- 記録は Slack への投稿が成功した後に書く。投稿に失敗した通知は記録が残らず、次の通知 (数時間後) で投稿し直す。Pub/Sub トリガーの再試行は使わない
- 予測 (`forecastThresholdExceeded`) の閾値は使わない (予算 `budget-alarmify-prod` に予測ルールが無い)
- 本文の例:

  ```text
  :warning: 予算アラート: budget-alarmify-prod の支出が予算の 50% を超えました
  支出 ￥5,123 / 予算 ￥10,000 (集計開始 2026-09-01T00:00:00Z)
  https://console.cloud.google.com/billing/013124-184724-31547F/budgets
  ```

## 1. Pub/Sub トピックを作り、予算に紐づける (bannzai。オーナー権限)

`gcloud` の既定プロジェクトが別アプリのため `--project=alarmify-prod` を明示する。トピックの作成は非冪等 (既にあれば `ALREADY_EXISTS` で失敗する) なので、先に一覧で確認する。

```sh
gcloud pubsub topics list --project=alarmify-prod --format='value(name)'
gcloud pubsub topics create budget-alarmify-prod --project=alarmify-prod

# 予算にトピックを紐づける (更新するのはこのフラグだけで、既存の email チャンネル・閾値はそのまま残る)。
# 呼び出し元にトピックの pubsub.topics.setIamPolicy が要る (API が Cloud Billing のサービスエージェントに publisher を付与する)
gcloud billing budgets update billingAccounts/013124-184724-31547F/budgets/655b729c-8d1e-4e9f-a458-dbce538d6c6d \
  --notifications-rule-pubsub-topic=projects/alarmify-prod/topics/budget-alarmify-prod
```

確認 (read-only)。`notificationsRule` に `pubsubTopic` と `monitoringNotificationChannels` の両方が出ること、トピックの IAM に Cloud Billing のサービスアカウント (Google 管理。予算の更新 API が付与する) が `roles/pubsub.publisher` で付いていることを見る。publisher が無いと通知は届かない。

```sh
gcloud billing budgets describe billingAccounts/013124-184724-31547F/budgets/655b729c-8d1e-4e9f-a458-dbce538d6c6d \
  --format='json(displayName,notificationsRule)'
gcloud pubsub topics get-iam-policy budget-alarmify-prod --project=alarmify-prod
```

## 2. Secret `SLACK_BOT_TOKEN` を登録する (bannzai。デプロイの前提)

`defineSecret` で束ねているため、Secret Manager に無い間は `firebase deploy --only functions` が Functions 全体で失敗する (`REVENUECAT_WEBHOOK_AUTHORIZATION` と同じ)。値はシェルプロファイルで export 済みの `SLACK_BOT_TOKEN` (slack-notification-setup skill の前提) をそのまま使う。値をシェル履歴・ログに残さないよう、標準入力で渡す。

```sh
cd firebase
[ -n "$SLACK_BOT_TOKEN" ] || { echo "Error: SLACK_BOT_TOKEN is empty" >&2; exit 1; }
printf '%s' "$SLACK_BOT_TOKEN" | npx --yes firebase-tools@15.30.0 functions:secrets:set SLACK_BOT_TOKEN --project prod --data-file -
```

`functions:secrets:set` は同名の Secret があれば新しいバージョンを追加する (冪等ではない)。登録済みかは `gcloud secrets list --project=alarmify-prod` で名前だけ確認できる。bot token を作り直した (Slack App を再インストールした) 時は同じコマンドで新しい値を登録し、関数を再デプロイする (Secret は起動時に読む)。

## 3. 初回デプロイ (bannzai。オーナーの gcloud アカウントでローカルから)

Pub/Sub トリガーの関数を初めて作る時、firebase-tools はトピックの作成 (`pubsub.topics.create`) と、Pub/Sub のサービスエージェントへの `roles/iam.serviceAccountTokenCreator`・実行サービスアカウント (compute) への `roles/run.invoker` と `roles/eventarc.eventReceiver` の付与 (`resourcemanager.projects.setIamPolicy`) を行う。GitHub Actions のデプロイ用サービスアカウント (`github-firebase-deployer`) にはどちらの権限も無い (`roles/firebase.admin` / `roles/cloudfunctions.admin` は `getIamPolicy` まで) ため、初回の作成はオーナーのアカウントでローカルから行う。関数が一度作られた後の更新は、トピックの作成もロールの付与も行わないので、これまでどおり GitHub Actions (`functions-deploy.yml`) でデプロイできる。

```sh
# main にマージした後、main の checkout で実行する (対象をこの関数だけに絞る)
make deploy-functions FUNCTIONS=budgetAlertToSlack
```

確認 (read-only):

```sh
gcloud functions describe budgetAlertToSlack --region=asia-northeast1 --project=alarmify-prod --v2 \
  --format='value(state,eventTrigger.pubsubTopic,eventTrigger.eventType)'
gcloud projects get-iam-policy alarmify-prod --flatten='bindings[].members' \
  --filter='bindings.members:gcp-sa-pubsub OR bindings.members:320409781062-compute' \
  --format='table(bindings.role,bindings.members)'
```

## 4. 経路を確認する

Cloud Billing は閾値を超えていなくても 1 日に複数回メッセージを送るため、デプロイから数時間以内に関数のログへ `budget notification` (`outcome: no_threshold`) が記録されれば、予算 → Pub/Sub → 関数の経路は通っている。

```sh
gcloud functions logs read budgetAlertToSlack --region=asia-northeast1 --project=alarmify-prod --limit=20
```

Slack への投稿まで確かめるには、公式ドキュメントと同じ形式の閾値超過メッセージをトピックへ手で publish する。`budgetId` 属性には実際の予算の ID ではなくテスト用の値を使う (実際の ID で publish すると `budgetNotifications/{budgetId}` に 50% を投稿済みと記録され、本物の 50% 通知が投稿されなくなる)。

```sh
gcloud pubsub topics publish budget-alarmify-prod --project=alarmify-prod \
  --attribute=billingAccountId=013124-184724-31547F,budgetId=manual-test,schemaVersion=1.0 \
  --message='{"budgetDisplayName":"budget-alarmify-prod (manual test)","costAmount":5123,"costIntervalStart":"2026-09-01T00:00:00Z","budgetAmount":10000,"budgetAmountType":"SPECIFIED_AMOUNT","alertThresholdExceeded":0.5,"currencyCode":"JPY"}'
```

`#alarmify-notification` に本文が届き、ログに `outcome: posted` が出れば完了。同じメッセージをもう一度 publish すると `already_notified` になり投稿されない (冪等)。テストで作った `budgetNotifications/manual-test` は残しても本物の予算 (別の budgetId) には影響しないが、次の確認で `posted` を再現したい時は Firebase Console か firebase-admin で消す。

実際の閾値超過で届くことは、平常時の支出 (月 ¥100 未満) では起きないため、初めて 50% (¥5,000) を超えた時に届いた投稿で確認する。早く確かめたい場合は予算額を一時的に下げる (`gcloud billing budgets update ... --budget-amount=100JPY`。通知は数時間遅れる) 手もあるが、判断事項のため手順には含めない。

## よくある失敗

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| 関数のログに何も出ない | 予算にトピックが紐づいていない、またはトピックの IAM に Cloud Billing の publisher が無い | 手順 1 の確認コマンドで `pubsubTopic` と `roles/pubsub.publisher` を見る |
| `Slack chat.postMessage に失敗しました: not_in_channel` | bot が `#alarmify-notification` に参加していない | `bash ~/.agents/skills/slack-notification-setup/scripts/setup-notification-channel.sh --service alarmify --check` で参加状態を見て、未参加なら `--check` 無しで適用する |
| `invalid_auth` / `token_revoked` | Secret の token が失効している | Slack App を再インストールして新しい bot token を手順 2 で登録し、再デプロイする |
| `firebase deploy` が `SLACK_BOT_TOKEN` の不在で止まる | Secret 未登録 | 手順 2 |
| GitHub Actions のデプロイが IAM の変更失敗で止まる | 関数の初回作成を CI で行った | 手順 3 のとおり初回だけローカルからデプロイする |

## ローカル (エミュレータ) での扱い

- `make test-functions` のテスト (`firebase/functions/test/budgetAlert.test.ts`) は Secret も Slack も使わず、`notifyBudgetThreshold(deps, ...)` に偽の投稿関数を渡して、閾値の判定と投稿済みの記録 (冪等性) を検証する
- `make emulators` で関数を起動する時は `firebase/functions/.secret.local` に `SLACK_BOT_TOKEN=<任意の値>` を書く (`*.local` は git 管理外)。Pub/Sub エミュレータは起動していないため、関数の呼び出しはテストで代替する
