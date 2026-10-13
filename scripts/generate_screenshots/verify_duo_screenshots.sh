#!/usr/bin/env bash
#
# verify_duo_screenshots.sh
#
# 【どのようなスクリプトか】
# generate_duo_screenshots.sh が出力した iPhone Duo 用の App Store スクリーンショットを機械検証する。
# 指定した言語 × バリアント内インデックスのすべてについて、次の 2 枚が揃っているかを確かめる。
#   - 外側ディスプレイ: {言語}/outer/{インデックス}.png が 1398×2034 px で alpha なし
#   - 内側ディスプレイ: {言語}/inner/{インデックス}.png が 2853×2007 px で alpha なし
# 寸法は Apple の「Screenshot specifications」の iPhone Duo の節
# (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。
# 内側は横向き (2853×2007) で作る (理由は generate_duo_screenshots.sh のヘッダー)。
# 1 つでも欠け・PNG 以外の形式・寸法違い・alpha ありがあれば [NG] を出して exit 1 で終わる。
#
# 【どうやって使用するか】
#   $ ./scripts/generate_screenshots/verify_duo_screenshots.sh <出力ディレクトリ> <言語のカンマ区切り> <インデックスのカンマ区切り>
#
# 例:
#   $ ./scripts/generate_screenshots/verify_duo_screenshots.sh \
#       scripts/generate_screenshots/artifacts/_duo/_variant-signal "ja,en-US" "0,1,2,3,4"
#
# 言語は fastlane のディレクトリ名 (map_language_to_fastlane の変換後。例: en-US) で渡す。
#
# 【終了コード】
#   0: すべて OK
#   1: NG あり
#   2: 引数不正
#
set -euo pipefail

OUTPUT_DIR="${1:-}"
LANGUAGES="${2:-}"
INDICES="${3:-}"

if [ -z "$OUTPUT_DIR" ] || [ -z "$LANGUAGES" ] || [ -z "$INDICES" ]; then
  echo "Usage: $0 <出力ディレクトリ> <言語のカンマ区切り> <インデックスのカンマ区切り>" >&2
  exit 2
fi

ng_count=0
ok_count=0

# 1 枚の画像が PNG 形式で期待する寸法、alpha なしかを検査し、結果を [OK]/[NG] で表示する関数
# 引数: $1 ファイルパス, $2 期待する幅, $3 期待する高さ
check_png() {
  local file=$1
  local expected_width=$2
  local expected_height=$3

  if [ ! -f "$file" ]; then
    echo "[NG] ファイルが無い: $file"
    ng_count=$((ng_count + 1))
    return
  fi

  # sips の出力 (例: "  pixelWidth: 1398") から値だけを取り出す。1 行目はファイルのパスなので、
  # パスにキー名 (format 等) が含まれても拾わないよう、行頭のキー名で一致させる。
  # format は拡張子ではなく中身から判定される (JPEG を .png に改名したものは format: jpeg になる)
  local sips_output format width height has_alpha
  sips_output=$(sips -g format -g pixelWidth -g pixelHeight -g hasAlpha "$file")
  format=$(echo "$sips_output" | awk '$1 == "format:" {print $2}')
  width=$(echo "$sips_output" | awk '$1 == "pixelWidth:" {print $2}')
  height=$(echo "$sips_output" | awk '$1 == "pixelHeight:" {print $2}')
  has_alpha=$(echo "$sips_output" | awk '$1 == "hasAlpha:" {print $2}')

  if [ "$format" = "png" ] && [ "$width" = "$expected_width" ] && [ "$height" = "$expected_height" ] && [ "$has_alpha" = "no" ]; then
    ok_count=$((ok_count + 1))
  else
    echo "[NG] $file: format=${format} ${width}x${height} hasAlpha=${has_alpha} (期待: format=png ${expected_width}x${expected_height} hasAlpha=no)"
    ng_count=$((ng_count + 1))
  fi
}

IFS=',' read -ra language_list <<< "$LANGUAGES"
IFS=',' read -ra index_list <<< "$INDICES"

for language in "${language_list[@]}"; do
  for index in "${index_list[@]}"; do
    check_png "$OUTPUT_DIR/$language/outer/${index}.png" 1398 2034
    check_png "$OUTPUT_DIR/$language/inner/${index}.png" 2853 2007
  done
done

expected_count=$((${#language_list[@]} * ${#index_list[@]} * 2))
echo "検証結果: OK ${ok_count} / 期待 ${expected_count} 枚 (${#language_list[@]} 言語 × ${#index_list[@]} ページ × 外側・内側), NG ${ng_count} 件"

if [ "$ng_count" -gt 0 ]; then
  exit 1
fi
