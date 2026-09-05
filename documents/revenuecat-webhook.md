# RevenueCat webhook (サーバー側プランの更新) の設定手順

RevenueCat の entitlement `pro` の状態を `users/{uid}.plan` に反映する Functions `revenueCatWebhook` を、本番で有効にするまでの手順。方式の選定と判定の規則は [ADR 0005](adr/0005-sync-plan-with-revenuecat-webhook.md)。

| 項目 | 値 |
| --- | --- |
| 関数 | `revenueCatWebhook` (`firebase/functions/src/api/revenueCatWebhook.ts`。`POST /` のみ) |
| 本番 URL | `https://asia-northeast1-alarmify-prod.cloudfunctions.net/revenueCatWebhook` |
| 認証 | リクエストの `Authorization` ヘッダーの値が Secret `REVENUECAT_WEBHOOK_AUTHORIZATION` と完全一致すること (一致しなければ 401) |
| RevenueCat project | `Signalarm` (proj42e2b4ed) |

## 1. Secret を登録する (bannzai。デプロイの前提)

`defineSecret` で束ねているため、Secret Manager に無い間は `firebase deploy --only functions` が Functions 全体で失敗する。値は RevenueCat 側にも同じ文字列を設定するので、推測されない長さのランダム文字列を作る。

```sh
mkdir -p ./tmp
# 値はファイルにだけ置き、シェル履歴・ログに残さない。登録後に消す
openssl rand -base64 48 | tr -d '\n' > ./tmp/revenuecat-webhook-authorization.txt
[ -s ./tmp/revenuecat-webhook-authorization.txt ] || { echo "Error: 値が空です" >&2; exit 1; }
npx --yes firebase-tools@15.28.2 functions:secrets:set REVENUECAT_WEBHOOK_AUTHORIZATION --project prod --data-file ./tmp/revenuecat-webhook-authorization.txt
```

`firebase functions:secrets:set` は同名の Secret があれば新しいバージョンを追加する (冪等ではなく、実行のたびに値が変わる。値を変えたら手順 2 の Dashboard 側も更新する)。登録済みかは `npx --yes firebase-tools@15.28.2 functions:secrets:access REVENUECAT_WEBHOOK_AUTHORIZATION --project prod` で確認できる (値が表示されるので画面共有中は実行しない)。

## 2. RevenueCat Dashboard で webhook を追加する (bannzai。Web UI のみ)

https://app.revenuecat.com/ → project `Signalarm` → **Integrations** → **Webhooks** → **Add new configuration**

| 設定 | 値 |
| --- | --- |
| Name | 任意 (例: `alarmify-prod plan sync`) |
| Webhook URL | `https://asia-northeast1-alarmify-prod.cloudfunctions.net/revenueCatWebhook` |
| Authorization header | 手順 1 でファイルに作った値をそのまま (接頭辞を付けない。関数はヘッダーの値全体を比較する) |
| Environment | Production と Sandbox の両方 (TestFlight の Sandbox 購入でも本番のバックエンドのプランを更新する) |
| Event types | すべて (関数側で `pro` に関係するイベントだけを反映する) |
| App | All apps |

保存後、Dashboard の **Send test event** で `TEST` イベントを送ると、関数が 200 (`{"event_id": ..., "outcomes": []}`) を返す。手順 1 のファイルは登録・設定が済んだら消す (`rm ./tmp/revenuecat-webhook-authorization.txt`)。

## 3. デプロイして確認する

```sh
gh workflow run functions-deploy.yml --ref main -f environment=prod -f functions=revenueCatWebhook
```

確認 (read-only):

```sh
# 関数が ACTIVE
gcloud functions describe revenueCatWebhook --region=asia-northeast1 --project=alarmify-prod --v2 --format='value(state,updateTime)'

# Authorization ヘッダー無しは 401 (Firestore には何も書かれない)
curl -i -X POST https://asia-northeast1-alarmify-prod.cloudfunctions.net/revenueCatWebhook \
  -H 'Content-Type: application/json' -d '{"api_version":"1.0","event":{"id":"x","type":"TEST","event_timestamp_ms":0}}'

# 受信ログ (uid は載せない。type / eventId / outcomes だけ)
gcloud functions logs read revenueCatWebhook --region=asia-northeast1 --project=alarmify-prod --limit=20
```

## ローカル (エミュレータ) での扱い

- `make test-functions` のテスト (`firebase/functions/test/revenueCatWebhook.test.ts`) は Secret を使わず、`createRevenueCatWebhook(deps, { authorization })` に値を直接渡す
- `make emulators` で関数を起動する時は、`firebase/functions/.secret.local` に `REVENUECAT_WEBHOOK_AUTHORIZATION=<任意の値>` を書く (`*.local` は Firebase CLI がエミュレータ専用に読む。git 管理外にする)。RevenueCat から手元のエミュレータには届かないため、`curl -H "Authorization: <値>"` で `http://127.0.0.1:5410/demo-alarmify/asia-northeast1/revenueCatWebhook` へイベントを投げて確認する
- アプリは接続先がエミュレータのアカウントでは `Purchases.logIn` を呼ばず、本番から切り替えた起動では残っている本番の identity を `logOut` で匿名に戻す (`AccountSession.linkPurchases`)。エミュレータに接続している間はペイウォールの購入・復元を行えない (`AccountSession.purchaseLinkState`)。購入の導線を確認する時は接続先を production にする

## 反映されるプランの規則 (要約)

| webhook イベント | `users/{uid}` |
| --- | --- |
| `entitlement_ids` に `pro` を含む購読イベント (INITIAL_PURCHASE / RENEWAL / CANCELLATION / UNCANCELLATION / BILLING_ISSUE / PRODUCT_CHANGE / EXPIRATION 等) | `plan: pro`、`proExpiresAt: expiration_at_ms` (請求猶予期間の終了が後ならそちら)。失効日時が過去なら `plan: free` |
| `TRANSFER` | `transferred_from` を free、`transferred_to` を期限なしの pro |
| `TEST`、`pro` を含まないイベント、匿名 App User ID だけのイベント | 変更なし (200 を返す) |
| 保存済みの `planEventAt` より古いイベント | 変更なし (`outcomes: ["stale"]`) |
| ドキュメントが無い uid | pro にする更新で、Firebase Auth にユーザーが存在する時だけ作る (`["applied"]`)。free にする更新は `["unknown_user"]`、Auth に無い uid は `["auth_user_missing"]`、削除処理中の目印がある uid は `["account_deleted"]` で変更なし |

上限の判定 (`effectivePlan`) は `proExpiresAt` を過ぎた pro を free として扱うため、失効の webhook が遅れても上限は解除されたままにならない。

## セッション再開

```sh
cd /Users/bannzai/worktrees/bannzai/Alarmify/issue-19
claude --resume f54463cf-18f3-4cca-85fa-cdac653211e3
```
