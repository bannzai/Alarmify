#!/bin/bash

export SCHEME="AlarmifySnapshotUITests"

# シミュレータの存在確認・自動作成 (ensure_simulator_exists) とランタイムバージョン解決
# (resolve_ios_runtime_version) の共通関数。DESTINATION の組み立てで使うため先頭で読み込む
source "$(dirname "${BASH_SOURCE[0]}")/../simulator_common.sh"

# 撮影に使う iOS ランタイムの実バージョン。Xcode 更新で 26.0 → 26.0.1 のように進み、
# 固定値では xcodebuild の destination に一致しなくなるため実行時に解決する
# (選定基準は resolve_ios_runtime_version を参照)。
# 空 (ランタイム無し) はここでは許容し、必須チェックは撮影を行うスクリプト側で行う
SNAPSHOT_OS_VERSION="${SNAPSHOT_OS_VERSION:-$(resolve_ios_runtime_version 26)}"
# App Store スクショ生成 (generate_screenshots) と同じデバイスを使い、シミュレータを増やさない
export DESTINATION="platform=iOS Simulator,name=${DESTINATION_SIM_NAME:-iPhone 13 Pro Max},OS=${SNAPSHOT_OS_VERSION}"
export DERIVED_DATA_PATH=artifacts/snapshot_ui_test/derived_data

# テストファイルパスからテスト実行パスとartifactパスを取得する共通関数
# Usage: get_test_info <test_file_path>
# Returns: TEST_PATH ARTIFACT_PATH (space separated)
get_test_info() {
  local test_file=$1

  # ファイル名から .swift を除去
  local filename=$(basename "$test_file" .swift)

  # テスト実行パス: AlarmifySnapshotUITests/{ClassName}/testSnapshot
  local test_path="AlarmifySnapshotUITests/${filename}/testSnapshot"

  # Artifactパス: artifacts/snapshot_ui_test/{ClassName}/testSnapshot
  local artifact_path="artifacts/snapshot_ui_test/${filename}/testSnapshot"

  echo "$test_path $artifact_path"
}
