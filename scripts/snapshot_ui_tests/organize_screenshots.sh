#!/usr/bin/env bash
#
# organize_screenshots.sh
#
# xcrun xcresulttool で抽出したスクリーンショットを整理するスクリプト
# manifest.json の suggestedHumanReadableName を解析して、ファイル名を変更
#
set -euo pipefail

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

echo "==== Organizing screenshots from manifest.json ===="

# jq を使用して manifest.json を解析
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
  # 例: "RetryPageSnapshotUITest---testSnapshot---ja---0_0_UUID.png"
  # '---' で分割して、最後から2番目が言語コード、最後がインデックス+UUID

  # まず .png を削除
  name_without_ext="${suggested_name%.png}"

  # 最後の3つの '---' で区切られた部分を取得
  # 正規表現で '---' の最後の出現を見つける
  # 戦略: 最後の '---' から逆順に処理

  # 最後の '---' 以降を取得 (index_and_uuid)
  index_and_uuid="${name_without_ext##*---}"
  # 最後の '---' を削除
  temp="${name_without_ext%---*}"

  # 次の最後の '---' 以降を取得 (language)
  language="${temp##*---}"
  # その '---' を削除
  temp="${temp%---*}"

  # 次の最後の '---' 以降を取得 (function_name)
  function_name="${temp##*---}"
  # その '---' を削除
  test_class="${temp%---*}"

  if [ -z "$test_class" ] || [ -z "$function_name" ] || [ -z "$language" ] || [ -z "$index_and_uuid" ]; then
    echo "Warning: Unexpected format: $suggested_name"
    echo "  test_class='$test_class', function_name='$function_name', language='$language', index_and_uuid='$index_and_uuid'"
    continue
  fi

  # index_and_uuid から '_0_' で分割して index を取得
  # 例: "0_0_UUID" -> index=0
  IFS='_' read -ra INDEX_PARTS <<< "$index_and_uuid"
  if [ ${#INDEX_PARTS[@]} -ge 1 ]; then
    index="${INDEX_PARTS[0]}"
  else
    index="0"
  fi

  # 出力先ディレクトリを作成: TESTNAME/INDEX/
  output_dir="$SCREENSHOTS_DIR/$test_class/$index"
  mkdir -p "$output_dir"

  # 新しいファイル名: {language}.png
  new_filename="${language}.png"
  dest_file="$output_dir/$new_filename"

  # ファイルを移動
  mv "$source_file" "$dest_file"
  echo "Organized: $exported_file -> $test_class/$index/$new_filename"
done

# README.md を生成
echo "==== Generating README.md for each test ===="
for test_class_dir in "$SCREENSHOTS_DIR"/*/; do
  # ディレクトリが存在しない場合はスキップ
  [ -d "$test_class_dir" ] || continue

  # テストクラス名を取得
  test_class=$(basename "$test_class_dir")

  # テストファイルを検索
  test_file=$(find AlarmifySnapshotUITests -type f -name "${test_class}.swift" 2>/dev/null | head -1)

  if [ -n "$test_file" ]; then
    # 撮影対象のソースを実在するファイルから特定する。
    # テストディレクトリの単純置換では、Features 配下に無い画面 (ContentView 等) が
    # 存在しないパスに変換されるため、{Page}.swift を本体ターゲットから検索する
    page_name=${test_class%SnapshotUITest}
    source_file=$(find Alarmify -name "${page_name}.swift" -not -path "*/SnapshotUITest/*" 2>/dev/null | head -1)
    if [ -n "$source_file" ]; then
      source_dir=$(dirname "$source_file")
    else
      # 見つからない場合は従来のディレクトリ置換にフォールバックする
      test_dir=$(dirname "$test_file")
      source_dir=${test_dir/AlarmifySnapshotUITests/Alarmify}
    fi

    # README.md を生成
    readme_file="$test_class_dir/README.md"
    cat > "$readme_file" <<EOF
# $test_class

## Source
\`${source_dir}/\`
EOF
    echo "Generated: $test_class/README.md -> $source_dir/"
  else
    echo "Warning: Test file not found for $test_class"
  fi
done

# 一時ファイルをクリーンアップ
echo "==== Cleaning up temporary files ===="
# exported files (UUIDファイル) を削除
find "$SCREENSHOTS_DIR" -maxdepth 1 -type f -name "*.png" -delete 2>/dev/null || true
# manifest.json を削除
rm -f "$MANIFEST_FILE"

echo "==== Organization complete ===="
echo "==== Screenshots organized in: $SCREENSHOTS_DIR ===="
