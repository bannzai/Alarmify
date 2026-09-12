# 設定

アートボード: `SettingsDark` / `SettingsLight`。現在の `SettingsView` を置き換える。セクション見出しは密な画面のため上 14 / 下 6。

## 構成

1. ナビ: `< Signalarm` / `Settings`
2. **Plan**: `Plan` → `Free` / `Pro` (値は `fg3`)。無料なら `Signalarm Pro` の行 (シェブロン) → ペイウォール (`.settings`)。Pro なら行を出さず、`Plan` の値を `Pro` にする (失効日時があれば `Pro until Oct 12` のように併記)
3. **Permissions**: `Alarms` → `Allowed` / `Denied` / `Not determined` (`AlarmKitScheduler.authorizationState`)、`Notifications` → 同様 (`UNUserNotificationCenter.notificationSettings`)。`Denied` の行はタップで OS の設定を開く (`UIApplication.openSettingsURLString`)、`Not determined` はその場で要求する
4. **Account**: `Account ID` → uid (等幅 13 `fg3`、中央を省略、`textSelection`)。`Support` → `Email` (メールアプリを開く。アカウント ID を本文に添える)
5. **Legal**: `Terms of Use` / `Privacy Policy` / `Legal Notice` / `Open Source Licenses` (既存のリンク先)
6. `Delete Account` (`destructive` の文字、単独カード)。確認ダイアログ・削除後の alert・エラー表示は既存の `SettingsView` のまま。削除の手順のリンク (`LegalLinks.accountDeletionGuide`) は確認ダイアログの message から辿れるようにし、行としては出さない
7. 開発者メニュー (DEBUG / TestFlight) は `Legal` の下に `Developer menu` の行として出す (accessibilityIdentifier `debug_menu` は維持)

## 確定コピー

| 要素 | en | ja |
| --- | --- | --- |
| タイトル | Settings | 設定 |
| セクション | Plan / Permissions / Account / Legal | プラン / 権限 / アカウント / 法務情報 |
| Plan | Plan / Free / Pro / Signalarm Pro | プラン / 無料 / Pro / Signalarm Pro |
| Permissions | Alarms / Notifications / Allowed / Denied / Not determined | アラーム / 通知 / 許可済み / 拒否 / 未確認 |
| Account | Account ID / Support / Email | アカウント ID / サポート / メール |
| Legal | Terms of Use / Privacy Policy / Legal Notice / Open Source Licenses | 利用規約 / プライバシーポリシー / 特定商取引法に基づく表記 / OSS ライセンス |
| 削除 | Delete Account | アカウントを削除 |
