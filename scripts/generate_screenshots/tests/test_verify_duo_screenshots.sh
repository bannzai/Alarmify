#!/usr/bin/env bash
# =============================================================================
# verify_duo_screenshots.sh のテスト
#
# magick で作った PNG を置き、揃っている時に exit 0、欠け・寸法違い・alpha ありの時に
# exit 1、引数不足の時に exit 2 になることを確かめる。simulator は使わない。
#
# 使い方:
#   bash scripts/generate_screenshots/tests/test_verify_duo_screenshots.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/../verify_duo_screenshots.sh"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
mkdir -p "$REPOSITORY_ROOT/tmp"
TEST_DIRECTORY="$(mktemp -d "$REPOSITORY_ROOT/tmp/verify-duo-test.XXXXXX")"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT INT TERM HUP

pass_count=0
fail_count=0

# 期待する exit code と実際の exit code を比べて PASS / FAIL を表示する
# 引数: $1 テスト名, $2 期待する exit code, $3 以降 実行するコマンド
assert_exit_code() {
  local name=$1
  local expected=$2
  shift 2
  local actual=0
  "$@" > "$TEST_DIRECTORY/last.log" 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name (期待 exit $expected、実際 exit $actual)"
    cat "$TEST_DIRECTORY/last.log"
    fail_count=$((fail_count + 1))
  fi
}

# 指定の寸法の alpha なし PNG を作る
# 引数: $1 出力パス, $2 幅, $3 高さ
make_png() {
  mkdir -p "$(dirname "$1")"
  magick -size "${2}x${3}" xc:white -alpha off "$1"
}

# 2 言語 × 2 ページの揃った出力を作る
make_complete_output() {
  local output_dir=$1
  local language index
  for language in ja en-US; do
    for index in 0 1; do
      make_png "$output_dir/$language/outer/${index}.png" 1398 2034
      make_png "$output_dir/$language/inner/${index}.png" 2853 2007
    done
  done
}

complete_dir="$TEST_DIRECTORY/complete"
make_complete_output "$complete_dir"
assert_exit_code "揃っている時は exit 0" 0 \
  bash "$VERIFY_SCRIPT" "$complete_dir" "ja,en-US" "0,1"

missing_dir="$TEST_DIRECTORY/missing"
make_complete_output "$missing_dir"
mv "$missing_dir/en-US/inner/1.png" "$TEST_DIRECTORY/moved.png"
assert_exit_code "1 枚欠けている時は exit 1" 1 \
  bash "$VERIFY_SCRIPT" "$missing_dir" "ja,en-US" "0,1"

wrong_size_dir="$TEST_DIRECTORY/wrong-size"
make_complete_output "$wrong_size_dir"
# 内側を縦向きの寸法にした時は、横向きの期待と食い違うため NG にする
make_png "$wrong_size_dir/ja/inner/0.png" 2007 2853
assert_exit_code "寸法が違う時は exit 1" 1 \
  bash "$VERIFY_SCRIPT" "$wrong_size_dir" "ja,en-US" "0,1"

alpha_dir="$TEST_DIRECTORY/alpha"
make_complete_output "$alpha_dir"
magick -size 1398x2034 xc:none "$alpha_dir/ja/outer/1.png"
assert_exit_code "alpha がある時は exit 1" 1 \
  bash "$VERIFY_SCRIPT" "$alpha_dir" "ja,en-US" "0,1"

assert_exit_code "引数が足りない時は exit 2" 2 \
  bash "$VERIFY_SCRIPT" "$complete_dir" "ja"

echo "結果: PASS=${pass_count} FAIL=${fail_count}"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
