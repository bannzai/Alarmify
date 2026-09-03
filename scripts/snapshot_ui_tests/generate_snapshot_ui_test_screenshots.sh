#!/usr/bin/env bash
#
# generate_snapshot_ui_test_screenshots.sh
#
# 【目的】
# AlarmifySnapshotUITests を実行し、全言語のスクリーンショットを取得するスクリプト。
# 日本語と他言語のスクリーンショットを比較して、翻訳の妥当性をチェックするために使用。
#
# 【使い方】
# 1. 全てのSnapshotUITestを実行:
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh
#
# 2. 最初のN個のテストのみ実行 (デバッグ用):
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -n 5
#
# 3. X番目のテストから開始 (CI並列実行用):
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 10 -n 5
#
# 4. 特定のテストのみ実行 (CI並列実行用):
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 5 -n 1
#
# 5. ビルドをスキップして実行 (CI並列実行用):
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh -b 2 -n 1 --skip-build
#
# 6. ヘルプを表示:
#    $ ./scripts/snapshot_ui_tests/generate_snapshot_ui_test_screenshots.sh --help
#
# 【具体的な用途】
# - リリース前の多言語UIチェック
# - UI変更後の視覚的回帰テスト
# - 翻訳の妥当性検証用スクリーンショット生成
#
# 【動作】
# 1. AlarmifySnapshotUITests/Features/**/*SnapshotUITest.swift を検索
# 2. build-for-testing でビルド
# 3. 各テストを test-without-building で実行 (-only-testing使用)
# 4. xcparse でスクリーンショットを抽出 (scripts/snapshot_ui_tests/screenshots/ に出力)
#
# 【注意事項】
# - Xcodeが必要
# - シミュレータが起動します
# - 実行には時間がかかる (テスト数 × 言語数 × 実行時間)
# - xcresulttoolを使用 (Xcodeに同梱)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/snapshot_ui_tests/snapshot_ui_test_env.sh

# trap ハンドラーが参照する変数は、simulator 準備・ビルド中の Ctrl+C でも
# unbound (set -u) にならないよう trap 登録前に初期化する
artifact_paths=()
failed_tests=""

# Ctrl+C (SIGINT) でのクリーンアップ処理
cleanup() {
  echo ""
  echo "==== Interrupted by user (Ctrl+C) ===="
  echo "==== Cleaning up... ===="

  # 既に取得したスクリーンショットは保持
  if [ ${#artifact_paths[@]} -gt 0 ]; then
    echo "==== Extracting screenshots from completed tests ===="
    for artifact_path in "${artifact_paths[@]}"; do
      if [ -d "$artifact_path" ]; then
        echo "Extracting: $artifact_path"

        # manifest.json が既に存在する場合は削除
        if [ -f "scripts/snapshot_ui_tests/screenshots/manifest.json" ]; then
          rm -f scripts/snapshot_ui_tests/screenshots/manifest.json
        fi

        xcrun xcresulttool export attachments --path "$artifact_path" --output-path scripts/snapshot_ui_tests/screenshots/ || true
      fi
    done

    # スクリーンショットを整理
    echo "==== Organizing screenshots ===="
    ./scripts/snapshot_ui_tests/organize_screenshots.sh scripts/snapshot_ui_tests/screenshots/ || true

    echo "==== Partial screenshots saved to: scripts/snapshot_ui_tests/screenshots/ ===="
  fi

  echo "==== Exited ===="
  exit 130  # 128 + SIGINT(2)
}

# SIGINT (Ctrl+C) をトラップ
trap cleanup SIGINT

# オプション解析
MAX_TESTS=""
BEGIN_INDEX=1
SKIP_BUILD=false
LANGUAGES=""
OVERWRITE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      # 数値以外だと head -n が失敗して対象が空になり、選択なしのエラーで止まるだけで原因が分かりにくいため、正の整数だけ受け付ける
      if ! [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: -n には正の整数を指定してください: '${2:-}'" >&2
        exit 1
      fi
      MAX_TESTS="$2"
      shift 2
      ;;
    -b)
      if ! [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: -b には正の整数を指定してください: '${2:-}'" >&2
        exit 1
      fi
      BEGIN_INDEX="$2"
      shift 2
      ;;
    -l|--languages)
      LANGUAGES="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --overwrite)
      OVERWRITE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -b N               開始するテストのインデックス (1から開始, デフォルト: 1)"
      echo "  -n N               実行するテスト数 (デフォルト: 全て)"
      echo "  -l LANGS           実行する言語をカンマ区切りで指定 (例: \"ja,en\", デフォルト: 全言語)"
      echo "  --skip-build       build-for-testing をスキップ (CI並列実行で既にビルド済みの場合)"
      echo "  --overwrite        既存スクリーンショットを削除して再撮影 (翻訳・画面の変更後に使う)"
      echo "  -h, --help         このヘルプメッセージを表示"
      echo ""
      echo "Examples:"
      echo "  # 全テスト実行"
      echo "  $0"
      echo ""
      echo "  # jaのみ実行"
      echo "  $0 -l \"ja\""
      echo ""
      echo "  # ja,enのみ実行"
      echo "  $0 -l \"ja,en\""
      echo ""
      echo "  # 2番目のテストから3個実行"
      echo "  $0 -b 2 -n 3"
      echo ""
      echo "  # 5番目のテストのみjaで実行"
      echo "  $0 -b 5 -n 1 -l \"ja\""
      echo ""
      echo "  # ビルドをスキップして実行 (CI並列実行用)"
      echo "  $0 -b 2 -n 1 --skip-build"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# 撮影 (ビルド・UITest 実行) には iOS 26 系ランタイムが必須。env 側は撮影しない経路からも
# source され得るため必須にせず、撮影の入口で検査する。
# --help はランタイム不在の環境でも表示できるよう、オプション解析より後に置く
if [ -z "$SNAPSHOT_OS_VERSION" ]; then
  echo "Error: 利用可能な iOS 26 系の simulator ランタイムが見つかりません (xcrun simctl list runtimes available で確認してください)" >&2
  exit 1
fi

# -l が区切り文字や空白だけ (-l ',' 等) だと対象言語が 0 件になり、完了判定が空ループで成功して 1 枚も撮らずに exit 0 になるため拒否する
if [ -n "$LANGUAGES" ] && [ -z "$(echo "$LANGUAGES" | tr ',' '\n' | tr -d ' ' | grep -v '^$')" ]; then
  echo "Error: -l に有効な言語が含まれていません: '$LANGUAGES'" >&2
  exit 1
fi

# 進行ログを見やすく
sep() { printf '\n==== %s ====\n' "$*"; }

# 対象言語リストを返す関数 (未指定時の全言語は AlarmifySnapshotUITests/Languages.swift の
# languageCodeAndLanguageWithRegion から読み取り、Swift 側と二重管理しない)
target_languages_list() {
  if [ -n "$LANGUAGES" ]; then
    echo "$LANGUAGES" | tr ',' '\n' | tr -d ' ' | grep -v '^$'
  else
    sed -nE 's/^[[:space:]]*\("([A-Za-z-]+)",.*/\1/p' AlarmifySnapshotUITests/Languages.swift
  fi
}

# テストファイルが撮影する Preview の個数を返す関数。テスト側の `let previewCount = N` が SSOT で、
# 一覧の SnapshotUITest<...>(previewCount:) と同じ値を持つ
preview_count_of() {
  local test_file=$1
  local count
  count=$(sed -nE 's/^[[:space:]]*let previewCount = ([0-9]+).*/\1/p' "$test_file" | head -1)
  echo "${count:-1}"
}

# 対象言語分のスクリーンショット PNG が揃っているかを判定する関数。
# ディレクトリ構造 {テストクラス}/{インデックス}/{言語}.png を、テストの previewCount 分の全インデックスで検証する
# (インデックス 0 だけで判定すると、複数 Preview のテストで 1 枚目だけ残った状態を完了と誤判定する)
snapshot_screenshots_complete() {
  local screenshot_dir=$1
  local test_file=$2
  [ -d "$screenshot_dir" ] || return 1

  local preview_count
  preview_count=$(preview_count_of "$test_file")
  local index lang
  for ((index = 0; index < preview_count; index++)); do
    for lang in $(target_languages_list); do
      if [ ! -f "$screenshot_dir/$index/${lang}.png" ]; then
        return 1
      fi
    done
  done
  return 0
}

# --overwrite 時に、対象テストの既存出力のうち対象言語分だけを削除する関数。
# ディレクトリごと消すと -l en --overwrite で ja.png (翻訳チェックの基準画像) まで失われるため、
# 選択した言語のファイルに限定する (言語未指定時は全言語が対象になる)
remove_snapshot_outputs() {
  local screenshot_dir=$1
  [ -d "$screenshot_dir" ] || return 0
  local lang
  for lang in $(target_languages_list); do
    find "$screenshot_dir" -mindepth 2 -maxdepth 2 -type f -name "${lang}.png" -delete
  done
}

sep "Preparing screenshots directory"
mkdir -p scripts/snapshot_ui_tests/screenshots

# シミュレータが存在しない場合は自動作成
ensure_simulator_exists

if [ "$SKIP_BUILD" = false ]; then
  rm -rf artifacts/snapshot_ui_test
  sep "Building SnapshotUITests"
  ./scripts/snapshot_ui_tests/build_snapshot_ui_test.sh
else
  sep "Skipping build (--skip-build specified)"
fi

sep "Collecting test files"
# AlarmifySnapshotUITests/Features配下のテストファイルを取得
# Components配下も含める
all_test_files=$(find AlarmifySnapshotUITests -type f -name "*SnapshotUITest.swift" | sort)
total_count=$(echo "$all_test_files" | wc -l | tr -d ' ')

# -b オプションで開始位置を調整
test_files=$(echo "$all_test_files" | tail -n +$BEGIN_INDEX)

# -n オプションが指定されている場合は制限
if [ -n "$MAX_TESTS" ]; then
  test_files=$(echo "$test_files" | head -n "$MAX_TESTS")
fi

# -b / -n の指定がテスト数と合わず 1 件も選ばれなかった時は、何も撮らずに All done. で成功しないよう失敗させる
if [ -z "$test_files" ]; then
  echo "Error: 実行するテストがありません (-b $BEGIN_INDEX, -n ${MAX_TESTS:-all}, テスト総数 $total_count)" >&2
  exit 1
fi

if [ -n "$MAX_TESTS" ]; then
  end_index=$((BEGIN_INDEX + MAX_TESTS - 1))
  sep "Running tests $BEGIN_INDEX to $end_index (total: $total_count)"
else
  sep "Running tests from $BEGIN_INDEX to $total_count (total: $total_count)"
fi

# テストを実行してartifactを収集
test_count=0

# set -e は無効化（テストが失敗しても継続）
set +e

for test_file in $test_files; do
  test_count=$((test_count + 1))
  current_index=$((BEGIN_INDEX + test_count - 1))
  sep "Processing test $current_index/$total_count: $test_file"

  # get_test_info でテスト実行パスとartifactパスを取得
  read -r test_path artifact_path <<< "$(get_test_info "$test_file")"

  sep "Test path: $test_path"
  sep "Artifact path: $artifact_path"
  
  # テストクラス名を取得 (例: AppSettingPageSnapshotUITest)
  test_class=$(basename "$test_file" .swift)
  screenshot_dir="scripts/snapshot_ui_tests/screenshots/$test_class"
  
  # --overwrite の場合は既存のスクリーンショット (対象言語分) を削除して再撮影する
  # (翻訳・画面の変更後に、古い画像がスキップ判定で残り続けないようにする)
  if [ "$OVERWRITE" = true ]; then
    remove_snapshot_outputs "$screenshot_dir"
  fi

  # 対象言語分のスクリーンショット PNG が既に揃っている場合はスキップする。
  # ディレクトリの存在だけで判定すると、別言語での追加実行 (-l ja の後の -l en) や
  # 中断で部分的に残ったディレクトリが永続的な成功扱いになるため、PNG の実在で判定する
  if snapshot_screenshots_complete "$screenshot_dir" "$test_file"; then
    sep "Skipping test: $test_file (screenshots already exist in $screenshot_dir)"
    continue
  fi
  
  # スキップするテストファイルのリスト (撮影対象から外したいテストが出たらここに追加する)
  ignore_files=()

  # テストファイル名がスキップリストに含まれているかチェック
  # (bash 3.2 では set -u 下で空配列の "${arr[@]}" が unbound になるため ${arr[@]+...} でガードする)
  should_skip=false
  for ignore_file in ${ignore_files[@]+"${ignore_files[@]}"}; do
    if [[ "$test_file" == *"$ignore_file"* ]]; then
      should_skip=true
      sep "Skipping test: $test_file (matched ignore pattern: $ignore_file)"
      break
    fi
  done

  if [ "$should_skip" = true ]; then
    continue
  fi

  # テスト実行（言語指定がある場合は第3引数として渡す）。
  # 失敗しても残りのテストは継続するが、失敗を収集して最後に非ゼロで終了する
  if ! ./scripts/snapshot_ui_tests/run_snapshot_ui_test.sh "$test_path" "$artifact_path" "$LANGUAGES"; then
    failed_tests+="  - $test_class"$'\n'
  fi

  # テスト実行直後にスクリーンショット抽出
  if [ -d "$artifact_path" ]; then
    sep "Extracting screenshots immediately: $artifact_path"

    # manifest.json が既に存在する場合は削除
    if [ -f "scripts/snapshot_ui_tests/screenshots/manifest.json" ]; then
      rm -f scripts/snapshot_ui_tests/screenshots/manifest.json
    fi

    xcrun xcresulttool export attachments --path "$artifact_path" --output-path scripts/snapshot_ui_tests/screenshots/ || true

    # スクリーンショットを整理
    sep "Organizing screenshots"
    ./scripts/snapshot_ui_tests/organize_screenshots.sh scripts/snapshot_ui_tests/screenshots/ || true

    # 抽出・整理の失敗 (xcresulttool の形式不整合等) は個別の exit code では拾い切れないため、
    # 対象言語分の PNG が実際に揃ったかで最終検証し、欠落していれば失敗として収集する
    if ! snapshot_screenshots_complete "$screenshot_dir" "$test_file"; then
      failed_tests+="  - $test_class (missing screenshots after extraction)"$'\n'
    fi
  else
    echo "Warning: Artifact not found: $artifact_path"
    failed_tests+="  - $test_class (result bundle not found)"$'\n'
  fi

  # artifactパスを配列に追加（cleanup用）
  artifact_paths+=("$artifact_path")
done

# テスト実行後は set -e を再有効化
set -e

# 失敗したテストがある場合は、不完全な生成結果を翻訳チェック側へ成功として渡さないよう非ゼロで終了する
if [ -n "$failed_tests" ]; then
  sep "ERROR: The following tests failed:"
  echo "$failed_tests"
  sep "Partial screenshots saved to: scripts/snapshot_ui_tests/screenshots/"
  exit 1
fi

sep "All done."
sep "Screenshots saved to: scripts/snapshot_ui_tests/screenshots/"
