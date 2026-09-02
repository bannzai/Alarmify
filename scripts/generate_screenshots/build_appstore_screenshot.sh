#!/usr/bin/env bash
#
# build_appstore_screenshot.sh
#
# App Storeスクリーンショット用のUITestをビルドするスクリプト。
# xcodebuild build-for-testing で事前ビルドする。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# 【使い方】
# $ ./scripts/generate_screenshots/build_appstore_screenshot.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

echo "==== Building AppStore Screenshot Tests ===="
xcodebuild build-for-testing \
  -project Alarmify.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH"

echo "==== Build completed ===="
