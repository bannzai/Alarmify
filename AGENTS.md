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
- 動作確認 (UI・挙動): `/ios-simulator` skill を起点にする。simulator は sim-boot 経由のプロジェクト固有 simulator を使い、アプリの起動は `make ios`
- push 経路の確認: APNs を使わずに `xcrun simctl push <UDID> com.bannzai.Alarmify documents/push-payloads/<ファイル>.apns` で simulator へ payload を投げられる。`schedule.apns` (Notification Service Extension 経由。`mutable-content: 1`) と `background.apns` (background push。`content-available: 1`) を用意している。payload の形式は `Alarmify/Shared/AlarmRequest.swift` が正
- AlarmKit の発火確認は「1〜2 分後のアラーム」で行う。発火判定は画面表示で行う (simulator は sound `.default` だと鳴らない癖がある)
- 実機確認: `make install-device` (接続中の実機へ install + launch)。APNs のデバイストークン取得・実 push の受信・App terminated / Device locked 状態の挙動は実機でしか検証できない
- public リポジトリのため、GitHub Actions の macOS runner 上のリモート simulator (simtunnel) も使える。caller workflow は `.github/workflows/simulator-session.yml` (Secrets `TS_OIDC_CLIENT_ID` / `TS_OIDC_AUDIENCE` の登録が前提)

## ストア素材

- App Store スクリーンショット: `AppStoreScreenshots/Sources/` のスクショページ (背景 + キャッチコピー + デバイスフレーム + モック画面) を `./scripts/generate_screenshots/generate_appstore_screenshots.sh` で撮影し、`./scripts/generate_screenshots/apply_variant.sh signal` で `fastlane/screenshots/{ja,en-US}/` へ配置してコミットする (手順・バリアント・撮影デバイスは `scripts/generate_screenshots/README.md`)。配色は `AppStoreScreenshots/Sources/DesignTokens.swift` が正で、LP (`docs/index.html`) とアプリアイコンに揃える。UITest はローカル simulator でしか実行できない
- 本番画面の多言語スクリーンショット (翻訳品質チェック): `./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh` (`.claude/skills/detect-mistranslation` が使う)。撮影対象の追加は `Alarmify/Features/SnapshotUITest/SnapshotUITestPage.swift` と `AlarmifySnapshotUITests/Features/` の両方に行う
- ヘッダークリエイティブ (App Store の product page header / search results) と LP の OGP 画像: `bash scripts/generate_header_creative/generate_header_creative.sh` が `fastlane/creative_assets/` と `docs/og.png` を再生成する (冪等)。入稿前の検証は `/appstore-header-creative` skill の `check_header_asset.sh`
- アプリアイコン: `Alarmify/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024、alpha なし)。差し替え時は `/ios-app-icon-generator` skill を使い、`docs/icon.png` (512×512) も同じ画像から作り直す

## 公開サイトとバックエンド

- `docs/` は GitHub Pages (main の `/docs`) で配信する LP と法務ドキュメント。LP の検証は `bash ~/.agents/skills/landing-page-builder/scripts/verify-lp.sh --app-store-support --has-account docs/index.html`
- バックエンドは Firebase `alarmify-prod` (構成: `documents/adr/0001-firebase-backend.md`、DB の規約: `.claude/rules/firestore-db-rules.md`)。ローカルは `demo-alarmify` のエミュレータで動かし、デプロイは `--project prod` を明示する

## 秘匿情報

- public リポジトリのため、API キー・APNs の認証キー (.p8)・Apple ID・Team ID の実値をコミットしない。ローカルでは direnv の `.envrc` (git 管理外) に置く
