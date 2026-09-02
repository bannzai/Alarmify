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
- 動作確認 (UI・挙動): `/ios-simulator` skill を起点にする。simulator は sim-boot 経由のプロジェクト固有 simulator を使い、アプリの起動は `make ios`
- push 経路の確認: APNs を使わずに `xcrun simctl push <UDID> com.bannzai.Alarmify documents/push-payloads/<ファイル>.apns` で simulator へ payload を投げられる。`schedule.apns` (Notification Service Extension 経由。`mutable-content: 1`) と `background.apns` (background push。`content-available: 1`) を用意している。payload の形式は `Alarmify/Shared/AlarmRequest.swift` が正
- AlarmKit の発火確認は「1〜2 分後のアラーム」で行う。発火判定は画面表示で行う (simulator は sound `.default` だと鳴らない癖がある)
- 実機確認: `make install-device` (接続中の実機へ install + launch)。APNs のデバイストークン取得・実 push の受信・App terminated / Device locked 状態の挙動は実機でしか検証できない
- public リポジトリのため、GitHub Actions の macOS runner 上のリモート simulator (simtunnel) も使える。caller workflow は `.github/workflows/simulator-session.yml` (Secrets `TS_OIDC_CLIENT_ID` / `TS_OIDC_AUDIENCE` の登録が前提)

## 秘匿情報

- public リポジトリのため、API キー・APNs の認証キー (.p8)・Apple ID・Team ID の実値をコミットしない。ローカルでは direnv の `.envrc` (git 管理外) に置く
