#!/usr/bin/env bash
#
# organize_appstore_screenshots.sh
#
# xcrun xcresulttool で抽出したスクリーンショットを fastlane 形式に整理するスクリプト。
# manifest.json の suggestedHumanReadableName を解析し、
# scripts/generate_screenshots/artifacts/_variant-{name}/{言語}/{インデックス}_{表示サイズ名}_{インデックス}.png
# の形式でリネーム・配置する (表示サイズ名は SCREENSHOT_DEVICE に対応する APP_IPHONE_67 / APP_IPHONE_65)。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# 【使い方】
# $ ./scripts/generate_screenshots/organize_appstore_screenshots.sh <SCREENSHOTS_DIR>
#
# 引数:
#   $1: SCREENSHOTS_DIR - xcresulttoolで抽出したスクリーンショットのディレクトリ
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

SCREENSHOTS_DIR="$1"

if [ ! -d "$SCREENSHOTS_DIR" ]; then
  echo "Error: Directory not found: $SCREENSHOTS_DIR"
  exit 1
fi

MANIFEST_FILE="$SCREENSHOTS_DIR/manifest.json"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "Error: manifest.json not found in $SCREENSHOTS_DIR"
  exit 1
fi

echo "==== Organizing App Store screenshots to fastlane format ===="

# jq が必要
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed"
  echo "Install with: brew install jq"
  exit 1
fi

# 各attachment を処理
jq -c '.[] | .attachments[]' "$MANIFEST_FILE" | while read -r attachment; do
  exported_file=$(echo "$attachment" | jq -r '.exportedFileName')
  suggested_name=$(echo "$attachment" | jq -r '.suggestedHumanReadableName')

  # ファイルが存在するか確認
  source_file="$SCREENSHOTS_DIR/$exported_file"
  if [ ! -f "$source_file" ]; then
    echo "Warning: File not found: $source_file"
    continue
  fi

  # suggestedHumanReadableName から情報を抽出
  # 例: "AppStoreScreenshot1PageSnapshotUITest---testSnapshot---ja---0_0_UUID.png"
  name_without_ext="${suggested_name%.png}"

  # '---' で逆順に分割して各要素を取得
  # 最後の '---' 以降を取得 (index_and_uuid)
  index_and_uuid="${name_without_ext##*---}"
  temp="${name_without_ext%---*}"

  # 言語コードを取得
  language="${temp##*---}"
  temp="${temp%---*}"

  # 関数名を取得
  function_name="${temp##*---}"
  # テストクラス名を取得
  test_class="${temp%---*}"

  if [ -z "$test_class" ] || [ -z "$function_name" ] || [ -z "$language" ] || [ -z "$index_and_uuid" ]; then
    echo "Warning: Unexpected format: $suggested_name"
    continue
  fi

  # テストクラス名からスクリーンショット番号を抽出
  # AppStoreScreenshot{N}PageSnapshotUITest → N を取得
  screenshot_number=$(echo "$test_class" | sed -E 's/AppStoreScreenshot([0-9]+)PageSnapshotUITest/\1/')

  if [ -z "$screenshot_number" ] || [ "$screenshot_number" = "$test_class" ]; then
    echo "Warning: Could not extract screenshot number from: $test_class"
    continue
  fi

  # バリアント名とバリアント内インデックスを取得
  variant_name=$(get_variant_name "$screenshot_number")
  variant_index=$(get_variant_index "$screenshot_number")

  # 言語コードを fastlane 形式にマッピング
  fastlane_lang=$(map_language_to_fastlane "$language")

  # variant別出力ディレクトリを作成
  output_dir="$VARIANT_OUTPUT_BASE_DIR/_variant-${variant_name}/$fastlane_lang"
  mkdir -p "$output_dir"

  # fastlane 形式のファイル名にリネームして配置 (表示サイズ名は撮影デバイスに対応。appstore_screenshot_env.sh の get_display_type が正)
  new_filename="${variant_index}_${SCREENSHOT_DISPLAY_TYPE}_${variant_index}.png"
  dest_file="$output_dir/$new_filename"

  mv "$source_file" "$dest_file"
  echo "Organized: $test_class ($language) -> _variant-${variant_name}/$fastlane_lang/$new_filename"
done

# 一時ファイルをクリーンアップ
echo "==== Cleaning up temporary files ===="
find "$SCREENSHOTS_DIR" -maxdepth 1 -type f -name "*.png" -delete 2>/dev/null || true
rm -f "$MANIFEST_FILE"

echo "==== Organization complete ===="
echo "==== Screenshots organized in: $VARIANT_OUTPUT_BASE_DIR/_variant-*/ ===="
