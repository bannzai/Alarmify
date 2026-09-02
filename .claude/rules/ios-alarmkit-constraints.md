---
paths:
  - "Alarmify/**/*.swift"
  - "AlarmifyNotificationService/**/*.swift"
  - "AlarmifyWidget/**/*.swift"
---

# iOS 通知・AlarmKit 制約ルール

取り込み元: bannzai/mementomorning の `ios-alarmkit-constraints.md` (一次検証は bannzai/Alarmy と iOS 26.5 SDK の swiftinterface で実施済み。経緯: https://github.com/bannzai/ideamemo/issues/187 のコメント)。Alarmify 固有の未検証事項は https://github.com/bannzai/IdeaMemo/issues/194 に集約する。

## AlarmKit (iOS 26+) の制約 (事実)

1. **iOS 26.0+ 専用。** `#available(iOS 26.0, *)` ガード必須 (本プロジェクトは deployment target が 26.0 のため不要だが、SDK の差分 API は `#available(iOS 26.1, *)` で分ける)
2. **NSAlarmKitUsageDescription が Info.plist に必須**
3. **件数上限あり** (`AlarmError.maximumLimitReached`)。外部サービスからの登録は上限に達し得るため、発火済み・過去日時のアラームは登録時に整理する
4. **cancelAll は存在しない。** UUID 個別キャンセルのみ。ID の対応付け (サーバー側のアラーム ID = AlarmKit の UUID) を永続化しておく
5. **AlarmMetadata 準拠型で ID 対応付けをする。** app と Widget Extension の両ターゲットに含める (実体: `Alarmify/Shared/AlarmifyAlarmMetadata.swift`)
6. **バックグラウンド wake しない。** AlarmKit 自体はアプリを起こさないため、サーバー起点の登録は push (Notification Service Extension / background push / ActivityKit) 側でプロセスを得る必要がある
7. **サイレントモード・集中モードを突破して鳴る**
8. **スワイプ消去は検知不可。** stopIntent も通らない
9. **システムのアラーム UI の停止ボタンは消せない・差し替えられない。** iOS 26.1 で `AlarmPresentation.Alert` の `stopButton` は deprecated になり、停止 UI はシステム標準描画

## Alarmify での運用ルール (方針)

1. **サーバーからの指示は `AlarmRequest` (push payload の `alarm` キー) に正規化し、`AlarmKitScheduler.apply` の 1 経路で AlarmKit に反映する。** Notification Service Extension・background push・将来の ActivityKit 経路のいずれも同じ関数を呼び、経路ごとに登録ロジックを分岐させない
2. **同じ id の再送は冪等にする。** `apply` は取消 → 登録で上書きするため、サーバーのリトライで二重登録しない
3. **再スケジュールはリアクティブにせず手続的に明示呼び出しする。** 状態変化検知の自動実行は不意の解除・登録がアンコントローラブルになるため避ける
4. **UserNotifications と併用する場合、主 (AlarmKit) のスケジュールを妨げないよう相手側のエラーは隔離する**
5. **Extension からの `AlarmManager.shared.schedule` が通るか、App terminated / Device locked で通るかは未検証。** 検証結果は https://github.com/bannzai/IdeaMemo/issues/194 のチェックリストと本ルールに追記する

## UserNotifications の制約 (事実)

1. **保留中通知は最大 64 件。** 超過分は直近 64 件のみ保持される
   - ref: https://developer.apple.com/documentation/usernotifications
2. **カスタムサウンドは AIFF 系のみ。** サイレントモード突破は不可 (Critical Alerts の申請が必要)
3. **Notification Service Extension は `mutable-content: 1` の visible push でしか起動せず、実行時間は約 30 秒。** `serviceExtensionTimeWillExpire` で必ず contentHandler を呼ぶ
