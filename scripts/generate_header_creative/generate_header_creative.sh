#!/bin/bash
# App Store creative assets (product page header / search results) と LP の OGP 画像 (docs/og.png) を生成する。
# SwiftUI (HeaderCreativeGenerator.swift) を swiftc でコンパイルし、header / search results の ja / en-US の
# 4 枚を fastlane/creative_assets/ へ、OGP 画像 1 枚を docs/og.png へ PNG 出力する。再実行しても同じ結果になる (冪等)。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# usage: bash scripts/generate_header_creative/generate_header_creative.sh [--safe-area-guide]
#   --safe-area-guide: Art Safe Area の赤枠を重ねた検証用画像を ./tmp/creative_assets_guide/ に出力する (成果物は更新しない)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
build_dir="$repo_root/tmp/generate_header_creative"
mkdir -p "$build_dir"

# 配色トークン (DesignTokens.swift) はスクショ基盤と共有し、二重定義を避ける
swiftc -O -parse-as-library \
  "$repo_root/AppStoreScreenshots/Sources/DesignTokens.swift" \
  "$script_dir/HeaderCreativeGenerator.swift" \
  -o "$build_dir/generate_header_creative"

# 引数のタイポで成果物 (fastlane/creative_assets, docs/og.png) を意図せず上書きしないよう、未知の引数は拒否する
case "${1:-}" in
  --safe-area-guide)
    "$build_dir/generate_header_creative" "$repo_root/tmp/creative_assets_guide" "$repo_root/tmp/creative_assets_guide/og.png" --safe-area-guide
    ;;
  "")
    "$build_dir/generate_header_creative" "$repo_root/fastlane/creative_assets" "$repo_root/docs/og.png"
    ;;
  *)
    echo "usage: bash scripts/generate_header_creative/generate_header_creative.sh [--safe-area-guide]" >&2
    exit 2
    ;;
esac
