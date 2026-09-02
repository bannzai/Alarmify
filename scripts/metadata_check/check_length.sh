#!/usr/bin/env bash
#
# check_length.sh - ファイルの文字数が上限以内かチェックするスクリプト
#
# 指定されたファイルの文字数が、指定された上限以内に収まっているかを検証します。
# App Store Connect のメタデータ（name, subtitle, keywords）の文字数制限チェックに使用します。
#
# 使い方:
#   ./check_length.sh <ファイルパス> <上限文字数>
#
# 例:
#   ./check_length.sh fastlane/metadata/ko/name.txt 30
#   ./check_length.sh fastlane/metadata/ko/keywords.txt 100
#
# 終了コード:
#   0: 文字数が上限以内
#   1: 文字数が上限を超えている
#   2: 引数エラーまたはファイルが存在しない
#
# 依存関係:
#   - wc コマンド（標準で利用可能）

set -euo pipefail

# --- ヘルプ表示 ---
if [[ "${1-}" == "-h" || "${1-}" == "--help" || $# -lt 2 ]]; then
  echo "使い方: $0 <ファイルパス> <上限文字数>"
  echo ""
  echo "例:"
  echo "  $0 fastlane/metadata/ko/name.txt 30"
  echo "  $0 fastlane/metadata/ko/keywords.txt 100"
  exit 2
fi

# --- 引数の取得 ---
FILE_PATH="$1"
MAX_LENGTH="$2"

# --- ファイル存在チェック ---
if [[ ! -f "$FILE_PATH" ]]; then
  echo "エラー: ファイルが存在しません: $FILE_PATH" >&2
  exit 2
fi

# --- 文字数の取得（改行を除く） ---
# trで改行を除去してからwc -mで文字数をカウント
CHAR_COUNT=$(tr -d '\n' < "$FILE_PATH" | wc -m | tr -d ' ')

# --- 判定と結果出力 ---
if [[ "$CHAR_COUNT" -le "$MAX_LENGTH" ]]; then
  echo "✅ OK: $FILE_PATH ($CHAR_COUNT / $MAX_LENGTH 文字)"
  exit 0
else
  echo "❌ NG: $FILE_PATH ($CHAR_COUNT / $MAX_LENGTH 文字) - 上限を超えています！" >&2
  exit 1
fi
