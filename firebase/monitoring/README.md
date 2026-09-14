# Cloud Monitoring のアラートポリシー

`alarmify-prod` のアラートポリシーのうち、リポジトリで定義を管理するものを置く。通知先の channel ID (Slack `#alarmify-notification` とメール) は gcp-alert-setup skill が作ったものを参照している (一覧: `gcloud alpha monitoring channels list --project=alarmify-prod`)。

| ファイル | 発火条件 | 見るもの |
| --- | --- | --- |
| `expired-alarms-outlived-ttl.policy.json` | `cleanupExpiredAlarms` が「TTL の猶予 48 時間を過ぎた期限切れ」を 1 件でも削除した (error ログ `expired alarms outlived the TTL policy`。条件は `jsonPayload.event="expired-alarms-outlived-ttl"`。message は firebase-functions の logger.error がスタックトレースを付けるため完全一致に使わない) | TTL ポリシーの状態と消し残しの件数 ([ADR 0008](../../documents/adr/0008-delete-expired-alarms-with-firestore-ttl.md)) |

`error-log-spike` (severity ERROR 以上が 5 分間に 10 件超) は gcp-alert-setup skill の管理で、ここには置かない。1 日 1 回の error ログ 1 行ではその閾値に届かないため、上のポリシーを別に持つ。

## 適用 (冪等)

同じ displayName のポリシーが無ければ作り、あれば上書きする。

```sh
bash firebase/monitoring/apply-policy.sh firebase/monitoring/expired-alarms-outlived-ttl.policy.json
```

確認:

```sh
gcloud alpha monitoring policies list --project=alarmify-prod \
  --filter='displayName:expired-alarms-outlived-ttl' \
  --format='yaml(name,enabled,conditions[].conditionMatchedLog.filter,notificationChannels)'
```

費用: 2027-09-01 からのアラートポリシー課金で、ログ一致条件 1 件 = メトリック参照 1 件として $0.35 / 月。ログ一致条件はポイントを返さないため、ポイント数の課金 ($0.50 / 100 万ポイント) は掛からない (https://cloud.google.com/products/observability/pricing の「Pricing for alerting」、2026-09-14 に確認)。
