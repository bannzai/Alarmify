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
| PURCHASE_HISTORY (購入履歴) | ANALYTICS, APP_FUNCTIONALITY | DATA_LINKED_TO_YOU | RevenueCat SDK が購入・購読情報を RevenueCat サーバーへ送信する。`Purchases.logIn` で Firebase Auth の uid を App User ID にしている (`Alarmify/Features/Purchase/ProEntitlement.swift`) | RevenueCat 公式は匿名 App User ID で個人を識別できない場合に DATA_NOT_LINKED_TO_YOU を選べると説明する ( https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy ) だが、uid で識別できるアカウントに購入履歴が紐づくため「ユーザーに紐付く」。RevenueCat の webhook がこの uid で `users/{uid}.plan` を更新する (#19) |
| OTHER_DIAGNOSTIC_DATA (その他の診断データ) | APP_FUNCTIONALITY | DATA_LINKED_TO_YOU | アラーム登録・取消の反映結果、失敗時のエラー、反映日時 | `AlarmApplyReportQueue` に保存した結果を `AlarmifyAPIClient.reportAlarmApply` が送信し、サーバーはユーザーのアラームに端末別の結果を保存する。履歴に登録の成否を表示するために用いる |

Sign in with Apple を実装した時点で、Apple から受け取るメールアドレス (中継アドレスを含む) を Firebase Auth が保持するため EMAIL_ADDRESS (APP_FUNCTIONALITY / DATA_LINKED_TO_YOU) を追加する。

## 収集しないデータ

| データ | 扱い |
|---|---|
| 位置情報・連絡先・写真・健康情報 | アクセスしない |
| 広告識別子 (IDFA) | 使用しない。ATT の対象なし |
| 操作の分析・クラッシュログ | Analytics / Crashlytics を導入しない (ADR 0001)。導入時は PRODUCT_INTERACTION / CRASH_DATA を追加する。アラームの反映結果・エラーは上記 OTHER_DIAGNOSTIC_DATA として宣言する |
| AlarmKit に登録したアラームの内容 | 端末内の AlarmKit が保持する。サーバー側の保存は上記 OTHER_USER_CONTENT として宣言済み |

## トラッキング

なし。ATT (App Tracking Transparency) の対象となるデータ結合・広告目的の共有は行わない。`PrivacyInfo.xcprivacy` の `NSPrivacyTracking` も `false`。

## Privacy Manifest (PrivacyInfo.xcprivacy)

### アプリ本体 (`Alarmify/PrivacyInfo.xcprivacy`)

| キー | 宣言 | 根拠 |
|---|---|---|
| NSPrivacyTracking | false | トラッキングなし |
| NSPrivacyCollectedDataTypes | UserID / DeviceID / OtherUserContent / OtherDiagnosticData (いずれも linked=true, tracking=false, purpose=AppFunctionality) | 自アプリのコードが自前 API へ送信するデータ。RevenueCat SDK の収集は SDK 同梱の manifest が宣言するため重複して書かない |
| NSPrivacyAccessedAPITypes | UserDefaults / CA92.1, 1C8F.1 | アプリ専用の課金キャッシュは CA92.1。通知 Extension と共有するアラーム ID・タイトル・未送信の反映結果等の App Group UserDefaults は 1C8F.1 |

Required Reason API の洗い出し (2026-09-12): UserDefaults のみ使用。ファイルタイムスタンプ・システム起動時刻・ディスク空き容量・アクティブキーボードの API は使用なし。Swift ソースに Required Reason API を追加した時は本表を更新する。

### Notification Service Extension / Widget Extension

`AlarmifyNotificationService/PrivacyInfo.xcprivacy` は UserDefaults / 1C8F.1 を宣言する。`NotificationService` → `AlarmKitScheduler.apply` が App Group にアラーム情報と反映結果を保存するため、通知 Extension の Resources にも manifest を含める。端末外への結果報告はアプリ本体が行うため、Extension 自体の収集データは空、tracking=false とする。

Widget Extension は ActivityKit から受け取った属性を表示するだけで、UserDefaults や外部通信を使わないため manifest は追加しない。

## 回答の確認根拠

2026-09-12 にソースと以下の公式資料を照合した。認証は `signInAnonymously` のみで、メールアドレスの収集はない。App Attest の attestation / assertion と App Check トークン、FCM の登録先識別子は既存の DEVICE_ID の説明に含める。Analytics SDK が無くても RevenueCat の購入履歴には ANALYTICS の回答が必要。

- Apple の収集データ・利用目的の定義: https://developer.apple.com/app-store/app-privacy-details/
- Apple の UserDefaults 利用理由: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- Firebase SDK の収集データ: https://firebase.google.com/docs/ios/app-store-data-collection
- RevenueCat の回答要件: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy

## ASC への適用方法

App Privacy は公開 App Store Connect API に存在しないため、`/appstore-app-privacy` skill (fastlane spaceship 経由) で `fastlane/app_privacy_details.json` を適用する。適用は申請時 (公開前チェックリスト issue) に行う。
