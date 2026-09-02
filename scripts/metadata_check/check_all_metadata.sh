#!/usr/bin/env bash
#
# check_all_metadata.sh - fastlane/metadata配下の全てのASO関連ファイルの文字数をチェック
#
# fastlane/metadata配下の全言語のname.txt、subtitle.txt、keywords.txtの
# 文字数がApp Store Connectの制限内に収まっているかを一括チェックします。
#
# 文字数制限:
#   - name.txt: 30文字以内
#   - subtitle.txt: 30文字以内
#   - keywords.txt: 100文字以内
#
# 使い方:
#   ./check_all_metadata.sh              # 全言語をチェック
#   ./check_all_metadata.sh ko           # 韓国語のみチェック
#   ./check_all_metadata.sh ja en-US ko  # 複数言語を指定
#
# 終了コード:
#   0: 全てのファイルが制限内
#   1: 1つ以上のファイルが制限を超えている
#
# 依存関係:
#   - check_length.sh（同ディレクトリに配置）

set -euo pipefail

# --- スクリプトのディレクトリを取得 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_LENGTH="$SCRIPT_DIR/check_length.sh"

# --- プロジェクトルートを取得 ---
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
METADATA_DIR="$PROJECT_ROOT/fastlane/metadata"

# --- ヘルプ表示 ---
if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  echo "使い方: $0 [言語コード...]"
  echo ""
  echo "例:"
  echo "  $0              # 全言語をチェック"
  echo "  $0 ko           # 韓国語のみチェック"
  echo "  $0 ja en-US ko  # 複数言語を指定"
  echo ""
  echo "文字数制限:"
  echo "  - name.txt: 30文字以内"
  echo "  - subtitle.txt: 30文字以内"
  echo "  - keywords.txt: 100文字以内"
  exit 0
fi

# --- check_length.shの存在確認 ---
if [[ ! -x "$CHECK_LENGTH" ]]; then
  echo "エラー: check_length.sh が見つからないか実行権限がありません: $CHECK_LENGTH" >&2
  exit 2
fi

# --- 言語ディレクトリの取得 ---
if [[ $# -gt 0 ]]; then
  # 引数で指定された言語のみ
  LANGUAGES=("$@")
else
  # 全言語を取得
  LANGUAGES=()
  for dir in "$METADATA_DIR"/*/; do
    if [[ -d "$dir" ]]; then
      LANGUAGES+=("$(basename "$dir")")
    fi
  done
fi

# --- チェック結果を格納 ---
HAS_ERROR=0
CHECKED_COUNT=0
ERROR_COUNT=0

echo "=========================================="
echo "App Store Metadata 文字数チェック"
echo "=========================================="
echo ""

# --- 各言語のファイルをチェック ---
for lang in "${LANGUAGES[@]}"; do
  LANG_DIR="$METADATA_DIR/$lang"

  if [[ ! -d "$LANG_DIR" ]]; then
    echo "警告: 言語ディレクトリが存在しません: $lang" >&2
    continue
  fi

  echo "📁 $lang"

  # name.txt (30文字)
  if [[ -f "$LANG_DIR/name.txt" ]]; then
    if ! "$CHECK_LENGTH" "$LANG_DIR/name.txt" 30; then
      HAS_ERROR=1
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
  fi

  # subtitle.txt (30文字)
  if [[ -f "$LANG_DIR/subtitle.txt" ]]; then
    if ! "$CHECK_LENGTH" "$LANG_DIR/subtitle.txt" 30; then
      HAS_ERROR=1
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
  fi

  # keywords.txt (100文字)
  if [[ -f "$LANG_DIR/keywords.txt" ]]; then
    if ! "$CHECK_LENGTH" "$LANG_DIR/keywords.txt" 100; then
      HAS_ERROR=1
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
  fi

  echo ""
done

# --- 結果サマリー ---
echo "=========================================="
if [[ $HAS_ERROR -eq 0 ]]; then
  echo "✅ 全てのファイルが制限内です ($CHECKED_COUNT ファイルをチェック)"
  exit 0
else
  echo "❌ $ERROR_COUNT 件のファイルが制限を超えています ($CHECKED_COUNT ファイルをチェック)"
  exit 1
fi
