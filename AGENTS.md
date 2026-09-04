# Alarmify

外部サービスからの HTTP リクエスト (Webhook / REST API) を契機に、ユーザーが操作していない iPhone の AlarmKit アラームを登録・更新する iOS アプリ。

## 概要
@documents/PROJECT.md

## Xcode プロジェクト構成の変更

- `Alarmify.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない (理由: [ADR 0002](documents/adr/0002-manage-xcode-project-directly.md)。機械検査: `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目)
- ターゲット、ファイル、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Alarmify.xcodeproj/project.pbxproj`、Scheme を `Alarmify.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 変更後は `git diff -- Alarmify.xcodeproj` で意図した差分だけであることを確認し、下記のビルドとテストを実行する
- ターゲット構成: `Alarmify` (app) / `AlarmifyTests` / `AlarmifyNotificationService` (Notification Service Extension。push 受信時に AlarmKit を呼ぶ検証経路) / `AlarmifyWidget` (AlarmKit の Live Activity 描画) / `AppStoreScreenshots` + `AppStoreScreenshotsUITests` (App Store スクリーンショットの撮影専用 app と UITest) / `AlarmifySnapshotUITests` (本番画面の多言語スクリーンショット撮影)。`Alarmify/Shared/` は app と Extension の両方に所属するファイルの置き場で、`AlarmMetadata` 準拠型は app と Widget の両ターゲット必須

## 検証方法

- シミュレータビルド: `make build-ios`、ユニットテスト: `make test` (simulator は sim-boot が用意する)。ログは `./tmp/build.log` 等に保存し、全文を warning / error で検査する
- 動作確認 (UI・挙動): `/ios-simulator` skill を起点にし、**特別な理由がない限り simtunnel (GitHub Actions macOS Runner 上のリモート iOS Simulator) で行う**。ローカル simulator (sim-boot) は既定にしない。issue や手順書にローカル前提の記述 (`simslim` の設定・`make ios` 等) があっても、それだけではローカルに倒す理由にしない
  - 手順: 検証対象のブランチを push してから `SIMTUNNEL_REPO=bannzai/Alarmify ~/ghq/github.com/bannzai/simtunnel/local/simtunnel up <セッション名> --ref <ブランチ> --wait` で起動する (`--ref` を省略すると main がビルドされる)。caller workflow は `.github/workflows/simulator-session.yml`、セッション名は worktree 名 (`issue-N` 等)。操作・スクリーンショットは `/ios-simulator` skill の `scripts/ios-wda.sh --session <セッション名>` (セッション途中から使う場合) か、`.mcp.json` に書き込んだ mobile-mcp 互換ツールで行う。確認が終わったら `simtunnel down <セッション名>` で閉じる (macOS runner の並列上限を CI と共有するため放置しない)
  - 到達困難な状態 (push 到着・課金状態等) は開発者メニューで作る (`.claude/rules/debug-menu-for-verification.md`)。リモートでは `xcrun simctl` や起動引数を使えないため、必要な操作が無ければ開発者メニューに追加してから検証する
  - ローカル sim-boot (`/sim-manager`、アプリ起動は `make ios`) に倒してよいのは、mobile-mcp 互換ツールの操作だけでは検証が成立しない場合に限る: Maestro E2E・XCUITest・StoreKit 検証・`xcrun simctl` を伴う手順 (`documents/push-payloads/` の `simctl push` を含む)。この場合は、ローカルに倒した理由を完了報告に明記する (使い分けの詳細は `/ios-simulator` skill Phase 1)
- push 経路の確認: APNs を使わずに `xcrun simctl push <UDID> com.bannzai.Alarmify documents/push-payloads/<ファイル>.apns` で simulator へ payload を投げられる。`schedule.apns` (visible push。`mutable-content: 1`) と `background.apns` (background push。`content-available: 1`) を用意している。payload の形式は `Alarmify/Shared/AlarmRequest.swift` が正。simulator で確認できるのは payload の形式と通知の表示までで、受信処理 (Notification Service Extension / `didReceiveRemoteNotification`) は走らない (下記「push → AlarmKit 登録の経路」)
- App Check: アプリ向け API (`appApi` / `deleteAccount`) は `X-Firebase-AppCheck` の App Check トークンを検証する。適用段階 (監視のみ / 強制) は `firebase/functions/.env.alarmify-prod` の `ALARMIFY_APP_CHECK_ENFORCEMENT` で切り替え、simulator ではデバッグトークンを環境変数 `FIRAAppCheckDebugToken` で渡す (simtunnel は `ios-wda.sh launch --env-file`、ローカルは `SIMCTL_CHILD_` 接頭辞)。登録・受け渡し・切り替えの手順と現在の段階は `documents/app-check.md`
- バックエンド (アプリ向け API) の確認: Firebase Auth の匿名認証は `CODE_SIGNING_ALLOWED=NO` のビルドだと keychain へアクセスできず失敗する。`make build-ios` / `make test` は simulator 向けを ad-hoc 署名する (証明書不要) ため、その成果物をそのまま install してよい。バックエンドを起動せずに API トークン画面やアカウント削除の画面フローを確認する時は、アプリの開発者メニュー (DEBUG / TestFlight のみ) で「通信をスタブに差し替える」を有効にする (スタブの削除は Firebase Auth の実アカウントを変えない)
- AlarmKit の発火確認は「1〜2 分後のアラーム」で行う。発火判定は画面表示で行う (simulator は sound `.default` だと鳴らない癖がある)。発火 UI は Live Activity として描画されるため、simslim を適用した simulator では `widgets` カテゴリのデーモンを残す (`simslim on <UDID> --except store,widgets`。既定の slim では `ActivityKit.ActivityError.connnection` で発火 UI が出ない)
- push → AlarmKit 登録の経路は simulator では検証できない。`xcrun simctl push` は SpringBoard がローカル通知として扱うため、visible push は Notification Service Extension を経由せずに表示され、`content-available` だけの payload は破棄されて `didReceiveRemoteNotification` も呼ばれない。この経路の確認は実機 + 実 APNs (#13) で行い、`AlarmRequest` → `AlarmKitScheduler.apply` の app 側の処理は開発者メニューの「push payload を適用」で確認する
- 課金の確認: 商品定義は `Alarmify.storekit` が正で、`AlarmifyTests/StoreKitConfigurationTests.swift` が `SKTestSession` (テストバンドルから読み込む) で商品解決・購入まで検証する (iOS 26.5 の simulator runtime では StoreKit Testing が機能しないため skip する)。Run の scheme は `Alarmify.storekit` を参照しない。`Config.local.xcconfig` に `appl_` キーを置いた時に RevenueCat が検証できないローカル生成のトランザクションにならないようにするためで、実ストア (sandbox) の購入導線はそのまま動く。RevenueCat の購入導線は API キーがある環境でのみ動き、無い環境ではペイウォールが価格を出さずに再読み込み導線を表示する (構成: [ADR 0004](documents/adr/0004-revenuecat-entitlement-and-api-key.md))
- バックエンド (`firebase/functions/`) のテスト: `make test-functions`。型検査の後、Firestore / Auth エミュレータ (`demo-alarmify`) 上で vitest を実行する (`npm --prefix firebase/functions test` と同じ。エミュレータの実行に JDK が必要)。lint は `npm --prefix firebase/functions run lint`。エミュレータのポートは `firebase/firebase.json` を正とし、アプリの接続先 (`Alarmify/API/AlarmifyBackend.swift`) もそれに揃える
- エミュレータだけを起動して API を手で叩く場合は `make emulators` (Firestore / Auth)。実プロジェクトへ接続するテストは書かない
- 実機確認: `make install-device` (接続中の実機へ install + launch)。APNs のデバイストークン取得・実 push の受信・App terminated / Device locked 状態の挙動は実機でしか検証できない

## 配布とデプロイ

- iOS の TestFlight 配布は `.github/workflows/ios-deploy.yml` (workflow_dispatch)。署名アセットの発行・Secrets の登録・初回配布までの手順は `documents/ios-testflight-distribution.md`
- Functions のデプロイはローカルが `make deploy-functions`、CI が `.github/workflows/functions-deploy.yml` (workflow_dispatch)。デプロイ先は `firebase/.firebaserc` の alias で明示する。手順は `documents/functions-deploy.md`

## ストア素材

- App Store スクリーンショット: `AppStoreScreenshots/Sources/` のスクショページ (背景 + キャッチコピー + デバイスフレーム + モック画面) を `./scripts/generate_screenshots/generate_appstore_screenshots.sh` で撮影し、`./scripts/generate_screenshots/apply_variant.sh signal` で `fastlane/screenshots/{ja,en-US}/` へ配置してコミットする (手順・バリアント・撮影デバイスは `scripts/generate_screenshots/README.md`)。配色は `AppStoreScreenshots/Sources/DesignTokens.swift` が正で、LP (`docs/index.html`) とアプリアイコンに揃える。UITest はローカル simulator でしか実行できない
- 本番画面の多言語スクリーンショット (翻訳品質チェック): `./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh` (`.claude/skills/detect-mistranslation` が使う)。撮影対象の追加は `Alarmify/Features/SnapshotUITest/SnapshotUITestPage.swift` と `AlarmifySnapshotUITests/Features/` の両方に行う
- ヘッダークリエイティブ (App Store の product page header / search results) と LP の OGP 画像: `bash scripts/generate_header_creative/generate_header_creative.sh` が `fastlane/creative_assets/` と `docs/og.png` を再生成する (冪等)。入稿前の検証は `/appstore-header-creative` skill の `check_header_asset.sh`
- アプリアイコン: `Alarmify/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024、alpha なし)。差し替え時は `/ios-app-icon-generator` skill を使い、`docs/icon.png` (512×512) も同じ画像から作り直す

## 公開サイトとバックエンド

- `docs/` は GitHub Pages (main の `/docs`) で配信する LP と法務ドキュメント。LP の検証は `bash ~/.agents/skills/landing-page-builder/scripts/verify-lp.sh --app-store-support --has-account docs/index.html`
- Functions の構成: アプリ向け API `appApi` (App Check トークンと Firebase Auth の ID トークンで認証。端末登録・API トークンの発行 / 失効・アラーム履歴)、外部サービス向け API `alarmsApi` (Bearer = API トークン。`POST /v1/alarms` / `DELETE /v1/alarms/{id}`)、保持期間 (30 日) を過ぎたアラーム要求を消す `cleanupExpiredAlarms`、アカウント削除の Callable `deleteAccount` とその掃除を完了させる `sweepDeletedAccountsHourly` (削除中の目印 `deletedAccounts/{uid}` がある間は `appApi` の書き込みを 410 で拒否し、目印は 2 時間後の sweep が最後の掃除と一緒に消す)。push payload は `Alarmify/Shared/AlarmRequest.swift` の形式に揃え、`mutable-content` と `content-available` の切り替えは環境変数 `ALARMIFY_PUSH_DELIVERY` (`notification-service` / `background`) で行う
- Firebase 関連のファイル (`firebase.json`・`.firebaserc`・`firestore.rules`・`firestore.indexes.json`・`functions/`) は `firebase/` 配下にまとめる (bannzai/shoppinglist と同じ構成)。バックエンドは Firebase `alarmify-prod` (構成: `documents/adr/0001-firebase-backend.md`、DB の規約: `.claude/rules/firestore-db-rules.md`)。ローカルは `demo-alarmify` のエミュレータで動かし、デプロイは `--project prod` を明示する

## 秘匿情報

- public リポジトリのため、API キー・APNs の認証キー (.p8)・Apple ID・Team ID の実値をコミットしない。ローカルでは direnv の `.envrc` (git 管理外) に置く
- 唯一の例外は `Alarmify/GoogleService-Info.plist`。Firebase の iOS 用 API キーは秘密鍵ではなくクライアントの識別子で、バイナリからも取り出せるためコミットする。代わりに bundle id 制限・Firestore の全パス deny・Functions 側の ID トークン認証・App Check (#4) で守る (判断と引き受けるリスク: [ADR 0003](documents/adr/0003-commit-google-service-info-plist.md))
- RevenueCat の public API key は `Config.xcconfig` の `REVENUECAT_API_KEY` から Info.plist へ渡す。App Store 用の実キー (`appl_`) は gitignore した `Config.local.xcconfig` に置く (手順は `Config.xcconfig` のコメント)
