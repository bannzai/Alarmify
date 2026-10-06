# 設定

アートボード: `SettingsDark` / `SettingsLight`。現在の `SettingsView` を置き換える。セクション見出しは密な画面のため上 14 / 下 6。

## 構成

1. ナビ: `< Signalarm` / `Settings`
2. **Plan**: `Plan` → `Free` / `Pro` (値は `fg3`)。無料なら `Signalarm Pro` の行 (シェブロン) → ペイウォール (`.settings`)。Pro なら行を出さず、`Plan` の値を `Pro` にする (失効日時があれば `Pro until Oct 12` のように併記)
3. **Permissions**: `Alarms` → `Allowed` / `Denied` / `Not determined` (`AlarmKitScheduler.authorizationState`)、`Notifications` → 同様 (`UNUserNotificationCenter.notificationSettings`)。`Denied` の行はタップで OS の設定を開く (`UIApplication.openSettingsURLString`)、`Not determined` はその場で要求する
4. **Account**: `Account ID` → uid (等幅 13 `fg3`、中央を省略、`textSelection`)。`Contact Us` の行 (シェブロン) → お問い合わせフォーム (`ContactUsView`。種別・内容・返信先のメールアドレスを送り、Slack へ通知する。メールで問い合わせたい人向けに、同じ画面に宛先のメールアドレスの行を出し、タップでメールアプリを開いてアカウント ID を本文に添える)
5. **Legal**: `Terms of Use` / `Privacy Policy` / `Legal Notice` / `Open Source Licenses` (既存のリンク先)
6. `Delete Account` (`destructive` の文字、単独カード)。確認ダイアログ・削除後の alert・エラー表示は既存の `SettingsView` のまま。確認は alert で出し、選択肢は `Delete` と `Cancel` だけにする
7. 開発者メニュー (DEBUG / TestFlight) は `Legal` の下に `Developer menu` の行として出す (accessibilityIdentifier `debug_menu` は維持)

## 確定コピー

| 要素 | en | ja |
| --- | --- | --- |
| タイトル | Settings | 設定 |
| セクション | Plan / Permissions / Account / Legal | プラン / 権限 / アカウント / 法務情報 |
| Plan | Plan / Free / Pro / Signalarm Pro | プラン / 無料 / Pro / Signalarm Pro |
| Permissions | Alarms / Notifications / Allowed / Denied / Not determined | アラーム / 通知 / 許可済み / 拒否 / 未確認 |
| Account | Account ID / Contact Us | アカウント ID / お問い合わせ |
| お問い合わせ | Contact Us / Type / Bug or issue / Feedback or request / Other / Message / Reply-to email / Send / Prefer email | お問い合わせ / 種別 / バグ・不具合 / ご意見・ご要望 / その他 / 内容 / 返信先のメールアドレス / 送信 / メールで問い合わせる |
| Legal | Terms of Use / Privacy Policy / Legal Notice / Open Source Licenses | 利用規約 / プライバシーポリシー / 特定商取引法に基づく表記 / OSS ライセンス |
| 削除 | Delete Account | アカウントを削除 |
