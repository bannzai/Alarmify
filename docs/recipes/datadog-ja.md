# Datadog

Datadog のモニターがアラート状態になったときに、Webhooks 連携から Signalarm API を直接呼びます。カスタムの JSON ペイロードと認証ヘッダーを設定するため、中継サーバーは不要です。

## 1. Webhooks 連携を設定する

Datadog の **Integrations → Webhooks** で、新しい Webhook を追加します。

| 設定 | 値 |
| --- | --- |
| Name | `signalarm` |
| URL | `https://api.signalarm.app/v1/alarms` |
| Encode as form | オフ |

**Custom Headers** に次の JSON を設定します。`<API_TOKEN>` は Signalarm アプリで発行した API トークンに置き換え、公開ファイルへ保存しないでください。

```json
{
  "Authorization": "Bearer <API_TOKEN>",
  "Content-Type": "application/json"
}
```

**Payload** は既定の内容を次の JSON に置き換えます。

```json
{
  "fire_in": 0,
  "title": "Datadog のアラート"
}
```

タイトルを固定することで、モニター名やメッセージの長さによる 200 文字制限の超過を避けます。監視対象ごとに Webhook を分け、短い固定タイトルに変えても構いません。待ち時間や配送の制約は [API リファレンス](../api) を参照してください。

## 2. アラート時だけ呼び出す

対象モニターの通知メッセージに、次を追加します。

```text
{{#is_alert}}
@webhook-signalarm
{{/is_alert}}
```

`@webhook-signalarm` はこの条件内だけに置いてください。条件外や復旧メッセージにも指定すると、復旧時にもアラームを作ります。警告やデータなし状態も、この例では通知しません。復旧しても、すでに予約したアラームは取り消しません。

モニターの再通知や Webhook の再送は追加のアラームを作る可能性があります。この例は `id` を指定せず毎回新規登録するため、同じ通知の再実行は冪等ではありません。再通知の間隔や対象を運用に合わせて設定してください。イベント単位の重複排除が必要なら、中継で同じイベントに同じ UUID を割り当てて API の `id` に渡します。全モニター共通の固定 UUID は、別の障害のアラームを上書きするので使いません。

## 3. テストする

モニターの **Test Notifications** でアラートへの遷移を選び、**Run Test** を実行します。Signalarm の履歴に「Datadog のアラート」が追加され、iPhone で発火することを確認してください。続けて復旧への遷移をテストし、新しいアラームが増えないことも確認します。テスト通知は実際にアラームを作ります。

届かない場合は Webhooks の設定とモニターの通知先を確認してください。API の認証エラー・利用上限などの応答は [API リファレンス](../api) に記載しています。HIPAA が有効なアカウントのセキュリティ通知には、Datadog 側の Webhook 制限があります。

## 公式資料

2026-09-16 にペイロード・条件付き通知・テスト手順を確認しました。

- https://docs.datadoghq.com/integrations/webhooks/
- https://docs.datadoghq.com/monitors/notify/variables/
- https://docs.datadoghq.com/monitors/notify/#test-notifications
