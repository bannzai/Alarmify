# App Privacy 回答 (App Store Connect)

App Store Connect の「App のプライバシー」への回答内容と、その実装根拠を記録する。回答定義の SSOT は `fastlane/app_privacy_details.json` (適用は `/appstore-app-privacy` skill)。アプリバンドル側の宣言は `Alarmify/PrivacyInfo.xcprivacy` が担い、判断根拠は本ドキュメントを共有する。

前提 (アーキテクチャ): 外部サービスからのアラーム要求を提供者のサーバー (Firebase。[ADR 0001](adr/0001-firebase-backend.md)) で受け、ユーザーの端末へ push で配送する。端末外へデータを送信する経路は、自前 API (Firebase Auth / Functions) と RevenueCat SDK (課金) の 2 つ。Analytics / Crashlytics / 広告 SDK は使わない。

## 結論サマリー

| ASC の質問 | 回答 |
|---|---|
| データを収集していますか | はい |
| トラッキングに使用していますか | いいえ |

## 収集するデータ

| category | purposes | data_protections | 実体 | 根拠 |
|---|---|---|---|---|
| USER_ID (ユーザー ID) | APP_FUNCTIONALITY | DATA_LINKED_TO_YOU | Firebase Auth の匿名 uid、API トークン (ハッシュ) | アカウントと API トークンの認証に必須。uid に紐づくため「ユーザーに紐付く」 |
| DEVICE_ID (デバイス ID) | APP_FUNCTIONALITY | DATA_LINKED_TO_YOU | APNs デバイストークン (FCM 登録トークン)、端末種別・OS・アプリのバージョン、App Check トークン (App Attest) | push の配送先。`users/{uid}/devices` に保存するため「ユーザーに紐付く」 |
| OTHER_USER_CONTENT (その他のユーザーコンテンツ) | APP_FUNCTIONALITY | DATA_LINKED_TO_YOU | 外部サービスから送られたアラームのタイトル・日時・送信元。30 日で削除 | 配送と履歴表示 (Pro) のためサーバーに保存する |
| PURCHASE_HISTORY (購入履歴) | ANALYTICS, APP_FUNCTIONALITY | DATA_NOT_LINKED_TO_YOU | RevenueCat SDK が購入・購読情報を RevenueCat サーバーへ送信する | RevenueCat 公式が最低要件とする回答 ( https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy )。`Purchases.logIn` で uid を連携する実装にした場合は DATA_LINKED_TO_YOU に変更する |

Sign in with Apple を実装した時点で、Apple から受け取るメールアドレス (中継アドレスを含む) を Firebase Auth が保持するため EMAIL_ADDRESS (APP_FUNCTIONALITY / DATA_LINKED_TO_YOU) を追加する。

## 収集しないデータ

| データ | 扱い |
|---|---|
| 位置情報・連絡先・写真・健康情報 | アクセスしない |
| 広告識別子 (IDFA) | 使用しない。ATT の対象なし |
| 利用状況・クラッシュ | Analytics / Crashlytics を導入しない (ADR 0001)。導入時は PRODUCT_INTERACTION / CRASH_DATA を追加する |
| AlarmKit に登録したアラームの内容 | 端末内の AlarmKit が保持する。サーバー側の保存は上記 OTHER_USER_CONTENT として宣言済み |

## トラッキング

なし。ATT (App Tracking Transparency) の対象となるデータ結合・広告目的の共有は行わない。`PrivacyInfo.xcprivacy` の `NSPrivacyTracking` も `false`。

## Privacy Manifest (PrivacyInfo.xcprivacy)

### アプリ本体 (`Alarmify/PrivacyInfo.xcprivacy`)

| キー | 宣言 | 根拠 |
|---|---|---|
| NSPrivacyTracking | false | トラッキングなし |
| NSPrivacyCollectedDataTypes | UserID / DeviceID / OtherUserContent (いずれも linked=true, tracking=false, purpose=AppFunctionality) | 自アプリのコードが自前 API へ送信する上記 3 種。RevenueCat SDK の収集は SDK 同梱の manifest が宣言するため重複して書かない |
| NSPrivacyAccessedAPITypes | UserDefaults / CA92.1 | 自アプリの UserDefaults 使用 (`Alarmify/Utils/DeviceTokenStore.swift` の App Group UserDefaults) |

Required Reason API の洗い出し (2026-09-02 時点、雛形): UserDefaults のみ使用。ファイルタイムスタンプ・システム起動時刻・ディスク空き容量・アクティブキーボードの API は使用なし。Swift ソースに Required Reason API を追加した時は本表を更新する。

### Notification Service Extension / Widget Extension

Extension のコードが Required Reason API を直接呼ぶ (UserDefaults 等) 場合は、アプリ本体の manifest では extension をカバーできないため、その Extension ターゲットにも PrivacyInfo.xcprivacy を追加する。雛形時点では `AppGroup.userDefaults` を Extension から呼んでいないため追加しない。

## ASC への適用方法

App Privacy は公開 App Store Connect API に存在しないため、`/appstore-app-privacy` skill (fastlane spaceship 経由) で `fastlane/app_privacy_details.json` を適用する。適用は申請時 (公開前チェックリスト issue) に行う。
