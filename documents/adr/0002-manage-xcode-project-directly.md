# 0002. Xcode プロジェクトを直接管理する

## Status
Accepted (2026-09-02)

## Context
初期の `Alarmify.xcodeproj` (app / Tests / Notification Service Extension / Widget Extension の 4 ターゲット) は XcodeGen の `project.yml` から生成した。`project.yml` と生成物の `project.pbxproj` を両方 Git で管理すると、片方だけが更新されても差異を検出する仕組みがなく、後から XcodeGen を実行した時に初めて設定の不一致やビルドエラーが表面化する。Xcode の GUI で加えた変更は `project.yml` に反映されず、次の生成で失われる (bannzai/mementomorning で実際に発生した経緯は同リポジトリの ADR 0002 を参照)。

## Decision
初期生成が終わった時点で `project.yml` を削除し、`Alarmify.xcodeproj` をプロジェクト構成の唯一の正として直接管理する。ターゲット、ファイル、ビルド設定、Scheme、Swift Package の変更には Xcode の GUI を使う。自動化が必要な場合は、プロジェクト構成を `project.pbxproj`、Scheme を `xcshareddata/xcschemes/*.xcscheme` で直接編集する。XcodeGen は使わず、`xcodegen generate` を実行しない。機械検査は `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目で行う。

## Consequences

**良い点:**
- `project.yml` と `project.pbxproj` の二重管理がなくなり、両者の不一致による遅延したビルド失敗を防げる
- Xcode の GUI で行った変更が後の再生成で失われない
- ブランチ統合時に生成物全体が書き換わることによる不要な競合を避けられる

**悪い点 / 引き受けるリスク:**
- `project.pbxproj` の差分は構造化された YAML より読みづらいため、変更時に意図しない差分がないか確認する必要がある
- Extension ターゲットの追加のような大きな構成変更は GUI 操作が必要になる。初期生成の時点で検証に必要な 4 ターゲットを揃えたのはこのため
