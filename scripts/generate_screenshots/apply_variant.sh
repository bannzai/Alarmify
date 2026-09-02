#!/usr/bin/env bash
#
# apply_variant.sh
#
# 選択したバリアントのスクリーンショットを fastlane/screenshots/ に適用するスクリプト。
# _variant-{name}/{lang}/* の内容を fastlane/screenshots/{lang}/* にコピー（上書き）する。
# App Store Connect にアップロードする前の準備用。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# 【使い方】
# $ ./scripts/generate_screenshots/apply_variant.sh <VARIANT_NAME>
#
# 引数:
#   $1: VARIANT_NAME - 適用するバリアント名
#       有効な値: ink (バリアントの一覧は appstore_screenshot_env.sh の get_variant_name が正)
#
# 例:
#   $ ./scripts/generate_screenshots/apply_variant.sh ink
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

VARIANT_NAME="${1:-}"
FASTLANE_DIR="fastlane/screenshots"
VARIANT_DIR="$VARIANT_OUTPUT_BASE_DIR/_variant-${VARIANT_NAME}"

# 引数チェック
if [ -z "$VARIANT_NAME" ]; then
  echo "Error: バリアント名を指定してください"
  echo ""
  echo "Usage: $0 <VARIANT_NAME>"
  echo ""
  echo "利用可能なバリアント:"
  ls -d "$VARIANT_OUTPUT_BASE_DIR"/_variant-* 2>/dev/null | sed 's|.*/_variant-||' || echo "  (なし)"
  exit 1
fi

# バリアントディレクトリの存在確認
if [ ! -d "$VARIANT_DIR" ]; then
  echo "Error: バリアントディレクトリが見つかりません: $VARIANT_DIR"
  echo ""
  echo "利用可能なバリアント:"
  ls -d "$VARIANT_OUTPUT_BASE_DIR"/_variant-* 2>/dev/null | sed 's|.*/_variant-||' || echo "  (なし)"
  exit 1
fi

echo "==== Applying variant: $VARIANT_NAME ===="
echo "==== Source: $VARIANT_DIR ===="
echo "==== Destination: $FASTLANE_DIR ===="

# バリアントの期待枚数 = このバリアントの番号帯に属するテストファイル数 × 撮影デバイス数 (SCREENSHOT_DEVICES)。
# 一部だけ生成した状態 (-n "1" や -d "69" 等) で適用すると、適用先の完成済み一式を消して欠落した素材を作るため、
# 各言語がデバイスごとに期待枚数に達していることを削除前に検証する
expected_count=0
for test_file in AppStoreScreenshotsUITests/Features/AppStoreScreenshot/AppStoreScreenshot*PageSnapshotUITest.swift; do
  [ -f "$test_file" ] || continue
  screenshot_number=$(basename "$test_file" .swift | sed -E 's/AppStoreScreenshot([0-9]+)PageSnapshotUITest/\1/')
  if [ "$(get_variant_name "$screenshot_number")" = "$VARIANT_NAME" ]; then
    expected_count=$((expected_count + 1))
  fi
done

if [ "$expected_count" -eq 0 ]; then
  echo "Error: バリアント '$VARIANT_NAME' に対応するテストが見つかりません"
  exit 1
fi

# 適用対象のデバイス (表示サイズ) 一覧。検証とコピーの両方をこの一覧に限定する
device_list=()
IFS=',' read -ra raw_device_list <<< "$SCREENSHOT_DEVICES"
for device in "${raw_device_list[@]}"; do
  device=$(echo "$device" | tr -d ' ')
  [ -n "$device" ] || continue
  device_list+=("$device")
done
if [ "${#device_list[@]}" -eq 0 ]; then
  echo "Error: SCREENSHOT_DEVICES に適用対象デバイスが指定されていません"
  exit 1
fi

# 適用対象の言語一覧を撮影言語の SSOT (AppStoreScreenshotsUITests/Languages.swift) から
# fastlane ディレクトリ名で組み立てる。バリアントディレクトリに実在する言語だけを検証すると、
# 言語ディレクトリごと欠けた素材 (-l ja だけで生成した等) を完全と誤判定して適用してしまうため、
# 必要な言語側から欠落を検証する
required_langs=""
while IFS= read -r language_code; do
  required_langs+="$(map_language_to_fastlane "$language_code")"$'\n'
done < <(sed -n 's/^ *("\([^"]*\)",.*/\1/p' AppStoreScreenshotsUITests/Languages.swift)
required_langs=$(echo "$required_langs" | grep -v '^$' || true)
if [ -z "$required_langs" ]; then
  echo "Error: AppStoreScreenshotsUITests/Languages.swift から対象言語を取得できません"
  exit 1
fi

incomplete=""
for lang in $required_langs; do
  lang_dir="$VARIANT_DIR/$lang/"
  if [ ! -d "$lang_dir" ]; then
    incomplete+="  - ${lang}: 言語ディレクトリがありません"$'\n'
    continue
  fi
  for device in "${device_list[@]}"; do
    display_type=$(get_display_type "$device")
    actual_count=$(ls -1 "$lang_dir"*_"${display_type}"_*.png 2>/dev/null | wc -l | tr -d ' ')
    if [ "$actual_count" -ne "$expected_count" ]; then
      incomplete+="  - ${lang} (${display_type}): ${actual_count}/${expected_count} 枚"$'\n'
    fi
  done
done

if [ -z "$(find "$VARIANT_DIR" -name '*.png' -print -quit 2>/dev/null)" ] || [ -n "$incomplete" ]; then
  echo "Error: バリアントのスクリーンショットが揃っていません: $VARIANT_DIR"
  if [ -n "$incomplete" ]; then
    echo "$incomplete"
  fi
  echo "先に ./scripts/generate_screenshots/generate_appstore_screenshots.sh で全番号・全デバイス (SCREENSHOT_DEVICES=$SCREENSHOT_DEVICES) を生成してください"
  exit 1
fi

# 対象言語 × 対象デバイスを適用する。コピーも device_list の表示サイズに限定し、
# バリアントディレクトリに残った選択外デバイスの古い PNG を持ち込まない。
# 選択外デバイスの適用済み PNG は削除もせず残す (選択したデバイスだけを差し替える)
applied=0
for lang in $required_langs; do
  lang_dir="$VARIANT_DIR/$lang/"
  dest_dir="$FASTLANE_DIR/$lang"
  mkdir -p "$dest_dir"

  file_count=0
  for device in "${device_list[@]}"; do
    display_type=$(get_display_type "$device")

    # 適用先に残った過去の PNG と混ざった一式を作らないよう、適用する表示サイズの既存 PNG を先に削除する
    find "$dest_dir" -maxdepth 1 -name "*_${display_type}_*.png" -delete 2>/dev/null || true

    # バリアントのスクリーンショットを適用先にコピー (存在は検証済みのため、失敗はそのまま異常終了させる)
    cp -f "$lang_dir"*_"${display_type}"_*.png "$dest_dir/"
    file_count=$((file_count + expected_count))
  done
  echo "Applied: $lang ($file_count files)"
  applied=$((applied + file_count))
done

echo "==== Apply complete: $applied files applied ===="
echo "==== Screenshots ready in: $FASTLANE_DIR ===="
