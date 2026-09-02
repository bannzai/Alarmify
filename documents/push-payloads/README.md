# push payload のサンプル

`xcrun simctl push <UDID> com.bannzai.Alarmify <ファイル>` で simulator に投げる検証用 payload。`Simulator Target Bundle` は simctl 専用のキーで、APNs には送らない。

- `schedule.apns` — visible push + `mutable-content: 1`。Notification Service Extension (`AlarmifyNotificationService`) が AlarmKit に登録する経路
- `background.apns` — background push (`content-available: 1`)。app 本体の `AppDelegate` が登録する経路
- `cancel.apns` — 登録済みアラームの取消

`fire_at` は過去日時だと AlarmKit が受け付けないため、検証時は現在時刻より数分後の ISO 8601 (UTC) に書き換えてから使う。payload の形式は `Alarmify/Shared/AlarmRequest.swift` が正。
