#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/snapshot_ui_tests/snapshot_ui_test_env.sh

TEST=$1
RESULT_BUNDLE_PATH=$2
LANGUAGES=${3:-""}  # 第3引数: 言語指定（省略可）カンマ区切り（例: "ja,en"）

echo "==== Running test: $TEST ===="
echo "==== Result bundle: $RESULT_BUNDLE_PATH ===="
if [ -n "$LANGUAGES" ]; then
  echo "==== Languages: $LANGUAGES ===="
fi

# Prevent: xcodebuild: error: Existing file at -resultBundlePath
rm -rf "$RESULT_BUNDLE_PATH"

# 言語フィルタリング用環境変数を設定。
# TEST_RUNNER_ プレフィックスにより、xcodebuild がテストランナープロセスに
# SNAPSHOT_LANGUAGES として環境変数を引き渡す (Languages.swift の filteredLanguages が読む。
# 素の export はランナープロセスへ届かず、フィルタが効かない)
if [ -n "$LANGUAGES" ]; then
  export TEST_RUNNER_SNAPSHOT_LANGUAGES="$LANGUAGES"
fi

xcodebuild test-without-building \
  -project Alarmify.xcodeproj \
  -scheme "$SCHEME" \
  -sdk iphonesimulator \
  -destination "$DESTINATION"  \
  -only-testing:"$TEST" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH"


echo "==== Test completed: $TEST ===="
