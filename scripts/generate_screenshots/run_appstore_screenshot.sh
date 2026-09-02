#!/usr/bin/env bash
#
# run_appstore_screenshot.sh
#
# 個別のApp Storeスクリーンショットテストを実行するスクリプト。
# xcodebuild test-without-building で事前ビルド済みのテストを実行する。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# 【使い方】
# $ ./scripts/generate_screenshots/run_appstore_screenshot.sh <TEST_PATH> <RESULT_BUNDLE_PATH> [LANGUAGES]
#
# 引数:
#   $1: TEST_PATH - テスト実行パス（例: AppStoreScreenshotsUITests/AppStoreScreenshot1PageSnapshotUITest/testSnapshot）
#   $2: RESULT_BUNDLE_PATH - 結果バンドル保存先（例: artifacts/appstore_screenshots/AppStoreScreenshot1PageSnapshotUITest/testSnapshot）
#   $3: LANGUAGES - 実行する言語（省略可、カンマ区切り例: "ja,en"）
#
# 注意:
#   言語フィルタリングは TEST_RUNNER_SNAPSHOT_LANGUAGES 環境変数で行う。
#   xcodebuild の TEST_RUNNER_ プレフィックス機構により、テストランナー
#   プロセスに SNAPSHOT_LANGUAGES として引き渡される。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

TEST=$1
RESULT_BUNDLE_PATH=$2
LANGUAGES=${3:-""}

echo "==== Running test: $TEST ===="
echo "==== Result bundle: $RESULT_BUNDLE_PATH ===="
if [ -n "$LANGUAGES" ]; then
  echo "==== Languages: $LANGUAGES ===="
fi

# 言語フィルタリング用環境変数を設定
# TEST_RUNNER_ プレフィックスにより、xcodebuildがテストランナープロセスに
# SNAPSHOT_LANGUAGES として環境変数を引き渡す
if [ -n "$LANGUAGES" ]; then
  export TEST_RUNNER_SNAPSHOT_LANGUAGES="$LANGUAGES"
else
  # 引数省略 = 全言語。呼び出し元の環境から継承した絞り込みが残ると一部の言語しか撮れず、完了判定と食い違うため解除する
  unset TEST_RUNNER_SNAPSHOT_LANGUAGES
fi

# 既存の結果バンドルを削除（xcodebuildエラー回避）
rm -rf "$RESULT_BUNDLE_PATH"

# テスト実行
xcodebuild test-without-building \
  -project Alarmify.xcodeproj \
  -scheme "$SCHEME" \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  -only-testing:"$TEST" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH"

echo "==== Test completed: $TEST ===="
