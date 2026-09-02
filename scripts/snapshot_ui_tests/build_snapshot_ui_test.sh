#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/snapshot_ui_tests/snapshot_ui_test_env.sh

echo "==== Building SnapshotUITests ===="
xcodebuild build-for-testing \
  -project Alarmify.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION"  \
  -derivedDataPath "$DERIVED_DATA_PATH"

echo "==== Build completed ===="
