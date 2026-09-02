# Alarmify

外部サービスからの HTTP リクエスト (Webhook / REST API) を契機に、ユーザーが操作していない iPhone の AlarmKit アラームを登録・更新する iOS アプリ。

## 概要
@documents/PROJECT.md

## Xcode プロジェクト構成の変更

- `Alarmify.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない (理由: [ADR 0002](documents/adr/0002-manage-xcode-project-directly.md)。機械検査: `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目)
- ターゲット、ファイル、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Alarmify.xcodeproj/project.pbxproj`、Scheme を `Alarmify.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 変更後は `git diff -- Alarmify.xcodeproj` で意図した差分だけであることを確認し、下記のビルドとテストを実行する
- ターゲット構成: `Alarmify` (app) / `AlarmifyTests` / `AlarmifyNotificationService` (Notification Service Extension。push 受信時に AlarmKit を呼ぶ検証経路) / `AlarmifyWidget` (AlarmKit の Live Activity 描画)。`Alarmify/Shared/` は app と Extension の両方に所属するファイルの置き場で、`AlarmMetadata` 準拠型は app と Widget の両ターゲット必須

## 検証方法

- シミュレータビルド: `make build-ios`、ユニットテスト: `make test` (simulator は sim-boot が用意する)。ログは `./tmp/build.log` 等に保存し、全文を warning / error で検査する
- 動作確認 (UI・挙動): `/ios-simulator` skill を起点にする。本リポジトリは public のため、**simtunnel (GitHub Actions macOS Runner 上のリモート iOS Simulator) を通じて行う**。caller workflow は `.github/workflows/simulator-session.yml`、セッション名は worktree 名 (`issue-N` 等) にし、確認が終わったら `simtunnel down` で閉じる (macOS runner の並列上限を CI と共有するため放置しない)
  - Maestro E2E・XCUITest・StoreKit 検証・`xcrun simctl` を伴う手順 (`documents/push-payloads/` の `simctl push` を含む) はリモート実行できないため、その場合のみローカル sim-boot (`/sim-manager`、アプリ起動は `make ios`) に倒す (使い分けの詳細は `/ios-simulator` skill Phase 1)
- push 経路の確認: APNs を使わずに `xcrun simctl push <UDID> com.bannzai.Alarmify documents/push-payloads/<ファイル>.apns` で simulator へ payload を投げられる。`schedule.apns` (Notification Service Extension 経由。`mutable-content: 1`) と `background.apns` (background push。`content-available: 1`) を用意している。payload の形式は `Alarmify/Shared/AlarmRequest.swift` が正
- バックエンド (アプリ向け API) の確認: Firebase Auth の匿名認証は `CODE_SIGNING_ALLOWED=NO` のビルドだと keychain へアクセスできず失敗する。`make build-ios` / `make test` は simulator 向けを ad-hoc 署名する (証明書不要) ため、その成果物をそのまま install してよい。バックエンドを起動せずに API トークン画面やアカウント削除の画面フローを確認する時は、アプリの開発者メニュー (DEBUG / TestFlight のみ) で「通信をスタブに差し替える」を有効にする (スタブの削除は Firebase Auth の実アカウントを変えない)
- AlarmKit の発火確認は「1〜2 分後のアラーム」で行う。発火判定は画面表示で行う (simulator は sound `.default` だと鳴らない癖がある)
- バックエンド: `npm --prefix functions install` の後、`npm --prefix functions test` で Firebase Emulator (auth / firestore / functions) を起動してテストを実行する。エミュレータのポートは `firebase.json` を正とし、他プロジェクトのエミュレータと衝突しない値にしている
- アプリからバックエンドを呼ぶ動作確認: `npm --prefix functions run serve` でエミュレータを起動し、アプリの開発者メニューで接続先を emulator に切り替えて再起動する。接続先の URL とポートは `Alarmify/API/AlarmifyBackend.swift` (`firebase.json` と揃える)
- 実機確認: `make install-device` (接続中の実機へ install + launch)。APNs のデバイストークン取得・実 push の受信・App terminated / Device locked 状態の挙動は実機でしか検証できない

## 配布とデプロイ

- iOS の TestFlight 配布は `.github/workflows/ios-deploy.yml` (workflow_dispatch)。署名アセットの発行・Secrets の登録・初回配布までの手順は `documents/ios-testflight-distribution.md`
- Functions のデプロイはローカルが `make deploy-functions`、CI が `.github/workflows/functions-deploy.yml` (workflow_dispatch)。デプロイ先は `.firebaserc` の alias で明示する。手順は `documents/functions-deploy.md`

## 公開サイトとバックエンド

- `docs/` は GitHub Pages (main の `/docs`) で配信する LP と法務ドキュメント。LP の検証は `bash ~/.agents/skills/landing-page-builder/scripts/verify-lp.sh --app-store-support --has-account docs/index.html`
- バックエンドは Firebase `alarmify-prod` (構成: `documents/adr/0001-firebase-backend.md`、DB の規約: `.claude/rules/firestore-db-rules.md`)。ローカルは `demo-alarmify` のエミュレータで動かし、デプロイは `--project prod` を明示する

## 秘匿情報

- public リポジトリのため、API キー・APNs の認証キー (.p8)・Apple ID・Team ID の実値をコミットしない。ローカルでは direnv の `.envrc` (git 管理外) に置く
- 唯一の例外は `Alarmify/GoogleService-Info.plist`。Firebase の iOS 用 API キーは秘密鍵ではなくクライアントの識別子で、バイナリからも取り出せるためコミットする。代わりに bundle id 制限・Firestore の全パス deny・Functions 側の ID トークン認証・App Check (#4) で守る (判断と引き受けるリスク: [ADR 0003](documents/adr/0003-commit-google-service-info-plist.md))
