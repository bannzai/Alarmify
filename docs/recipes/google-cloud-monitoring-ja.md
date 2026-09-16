# Google Cloud Monitoring

Cloud Monitoring のインシデント発生を iPhone のアラームで受け取ります。Monitoring の Webhook は独自の `incident` 形式を送るため、Signalarm API へ直接送信できません。このレシピでは既存の Home Assistant を中継に使い、`open` の通知だけを Signalarm のリクエストへ変換します。

## 1. 中継の準備

先に [Home Assistant のレシピ](./home-assistant) の手順 1・2 を適用し、API トークンを `secrets.yaml` に保存して `rest_command.alarmify_alarm` を定義してください。

Home Assistant は、Google Cloud から到達できる有効な証明書付きの HTTPS URL が必要です。この手順ではインターネットからアクセスできる既存環境を使います。ローカル専用の環境では、そのまま動きません。

Webhook 専用の秘密の ID を生成します。

```sh
openssl rand -hex 32
```

生成した値を `secrets.yaml` に追加します。Signalarm の API トークンとは別の値を使ってください。

```yaml
google_cloud_webhook_id: "<生成した秘密のID>"
```

## 2. アラートだけを転送する

`automations.yaml` に次を追加し、オートメーションを再読み込みします。同じ設定を重複して追加しないでください。

```yaml
- id: signalarm_google_cloud_monitoring
  alias: "Google Cloud のアラートを Signalarm へ転送"
  triggers:
    - trigger: webhook
      webhook_id: !secret google_cloud_webhook_id
      allowed_methods:
        - POST
      local_only: false
  conditions:
    - condition: template
      value_template: >-
        {{ trigger.json is defined
           and trigger.json is mapping
           and trigger.json.incident is defined
           and trigger.json.incident is mapping
           and trigger.json.incident.state is defined
           and trigger.json.incident.state == 'open' }}
  actions:
    - action: rest_command.alarmify_alarm
      data:
        fire_in: 0
        title: "Google Cloud のアラート"
```

タイトルは固定にして、外部のポリシー名が API の文字数上限を超えるのを避けています。監視対象ごとに変える場合は 200 文字以内にしてください。`closed` の復旧通知や `incident.state` のない接続テストは転送しません。復旧時に、すでに予約したアラームを取り消す処理はありません。

Webhook は ID を知っていれば呼べます。URL 全体をパスワードとして扱い、ログや公開ファイルへ記録しないでください。`local_only: false` は Google Cloud から受信するための設定です。

## 3. Monitoring の通知先に登録する

Google Cloud の **Monitoring → Alerting → Edit notification channels → Webhook → Add New** で、次の URL を登録します。

```text
https://<Home Assistant の公開ホスト>/api/webhook/<生成した秘密のID>
```

認証は追加せず、秘密の ID を含む HTTPS URL で受信します。Basic 認証や Signalarm の Bearer トークンはここには設定しません。**Test Connection** で受信を確認して保存し、対象のアラートポリシーの通知先にこの Webhook を選びます。

## 4. 発生と復旧を確認する

次の合成データで中継を確認できます。URL は自分の値へ置き換えてください。この操作は毎回新しいアラームを作ります。

```sh
curl --fail-with-body -X POST \
  'https://<Home Assistant の公開ホスト>/api/webhook/<生成した秘密のID>' \
  -H 'Content-Type: application/json' \
  -d '{"incident":{"state":"open"}}'
```

Home Assistant のオートメーショントレースで REST コマンドの実行を確認し、Signalarm の履歴と iPhone の発火を確認します。`fire_in: 0` の待ち時間や配送の制約は [API リファレンス](../api) を参照してください。同じリクエストの `open` を `closed` に変えると、新しいアラームを作らずに終了することも確認します。

最後に検証用の Monitoring ポリシーを発火・復旧させ、実際の通知でも同じ挙動になることを確認してください。接続テストの成功や中継の HTTP 成功応答だけでは、Signalarm への登録成功は保証されません。

この簡易中継は通知の重複排除や配送失敗時の自動再送を行いません。Monitoring の再通知や同じ `open` の再送でも新しいアラームが作られます。必要な通知だけを送るようポリシーを設定し、登録失敗は Home Assistant のトレースで確認してください。

## 公式資料

2026-09-16 に通知形式と Webhook 設定を確認しました。

- https://docs.cloud.google.com/monitoring/support/notification-options
- https://www.home-assistant.io/docs/automation/trigger/#webhook-trigger
