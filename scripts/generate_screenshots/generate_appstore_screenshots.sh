#!/usr/bin/env bash
#
# generate_appstore_screenshots.sh
#
# App Storeスクリーンショットを自動生成するメインスクリプト。
# AppStoreScreenshot 用の UITest をデバイス (6.9 インチ / 6.5 インチ) ごとに実行し、全言語のスクリーンショットを
# scripts/generate_screenshots/artifacts/_variant-{name}/ に生成する。
# (取り込み元: bannzai/mementomorning の同名スクリプト)
#
# 【目的】
# SwiftUI で構成した App Store スクリーンショット View を UITest で撮影し、
# バリアント別 artifacts に全言語分を配置する (fastlane への適用は apply_variant.sh)
#
# 【使い方】
# 1. 全スクリーンショットを全言語で生成:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh
#
# 2. 特定の言語のみで生成:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh -l "ja,en"
#
# 3. 特定の番号のスクリーンショットのみ生成:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh -n "1-6"
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh -n "1,3,5"
#
# 3-2. 特定のデバイス (表示サイズ) のみで生成 (デフォルトは 6.9 インチと 6.5 インチの両方):
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh -d "69"
#
# 4. 並列数を指定して実行:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh -p 2
#
# 5. ビルドをスキップして実行:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh --skip-build
#
# 6. 既存スクリーンショットを上書きして再生成:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh --overwrite
#
# 7. ヘルプを表示:
#    $ ./scripts/generate_screenshots/generate_appstore_screenshots.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../../"
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

# 一時ファイル・ディレクトリのクリーンアップ共通関数
cleanup_temp_files() {
  rm -rf "$TEMP_SCREENSHOTS_DIR"
}

# PIDとその全子孫プロセスを再帰的にkillする関数
# kill $(jobs -p) では直接の子プロセスしか停止できず、
# 孫プロセス（xcodebuild等）が孤児として残り続けるため再帰的に停止する
kill_descendants() {
  local pid=$1
  local children
  children=$(pgrep -P "$pid" 2>/dev/null || true)
  for child in $children; do
    kill_descendants "$child"
  done
  kill "$pid" 2>/dev/null || true
}

# Ctrl+C (SIGINT) / SIGTERM でのクリーンアップ処理
# プロセスグループ全体を停止して子プロセス（xcodebuild等）も確実に終了させる
cleanup() {
  trap - SIGINT SIGTERM
  echo "" >&3
  echo "==== Interrupted by user (Ctrl+C) ===" >&3
  echo ""
  echo "==== Interrupted by user (Ctrl+C) ===="
  local pids
  pids=$(jobs -p 2>/dev/null) || true
  for pid in $pids; do
    kill_descendants "$pid"
  done
  wait 2>/dev/null || true
  cleanup_temp_files
  echo "==== Partial screenshots may be in $VARIANT_OUTPUT_BASE_DIR ===" >&3
  echo "==== Partial screenshots may be in $VARIANT_OUTPUT_BASE_DIR ===="
  exit 130
}
trap cleanup SIGINT SIGTERM

# オプション解析
SKIP_BUILD=false
OVERWRITE=false
LANGUAGES=""
SCREENSHOT_NUMBERS=""
DEVICES="$SCREENSHOT_DEVICES"
# 並列数のデフォルトは 1 (直列)。同一シミュレータへの並列 test 実行はランナー同士が
# kill し合い "Early unexpected exit" で落ちることを実測したため (2026-08-16、iOS 26.0 sim)。
# -p 2 以上を使う時は DESTINATION_SIM_NAME で worktree ごとに専用シミュレータを分けても
# 同一シミュレータ内の並列は解決しない点に注意 (リトライで補完される)
PARALLEL=1
while [[ $# -gt 0 ]]; do
  case $1 in
    -l|--languages)
      LANGUAGES="$2"
      shift 2
      ;;
    -n|--numbers)
      SCREENSHOT_NUMBERS="$2"
      shift 2
      ;;
    -d|--devices)
      DEVICES="$2"
      shift 2
      ;;
    -p|--parallel)
      # 数値以外だと並列数の比較が失敗して上限なしで走り、同一シミュレータでランナーが衝突するため、正の整数だけ受け付ける
      if ! [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: -p には正の整数を指定してください: '${2:-}'" >&2
        exit 1
      fi
      PARALLEL="$2"
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
      echo "  -l LANGS           実行する言語をカンマ区切りで指定 (例: \"ja,en\", デフォルト: 全言語)"
      echo "  -n NUMS            実行するスクリーンショット番号を指定 (例: \"1,2,3\" or \"1-6\", デフォルト: 全番号)"
      echo "  -d DEVICES         撮影デバイス (表示サイズ) をカンマ区切りで指定 (69: 6.9インチ iPhone 17 Pro Max, 65: 6.5インチ iPhone 13 Pro Max。デフォルト: $SCREENSHOT_DEVICES)"
      echo "  -p NUM             並列実行数を指定 (デフォルト: 1。同一シミュレータでの並列はランナーが落ちやすい)"
      echo "  --skip-build       build-for-testing をスキップ"
      echo "  --overwrite        既存スクリーンショットを上書き（デフォルト: 全言語分揃っていればスキップ）"
      echo "  -h, --help         このヘルプメッセージを表示"
      echo ""
      echo "Examples:"
      echo "  # 全言語・全番号で生成"
      echo "  $0"
      echo ""
      echo "  # スクショ1のみ、日本語のみ"
      echo "  $0 -n \"1\" -l \"ja\""
      echo ""
      echo "  # ビルドスキップして逐次実行"
      echo "  $0 --skip-build -p 1"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# 撮影 (ビルド・UITest 実行) には iOS 26 系ランタイムが必須。env 側は apply_variant.sh など
# 撮影しない経路からも source されるため必須にせず、撮影の入口で検査する。
# --help はランタイム不在の環境でも表示できるよう、オプション解析より後に置く
if [ -z "$SCREENSHOT_OS_VERSION" ]; then
  echo "Error: 利用可能な iOS 26 系の simulator ランタイムが見つかりません (xcrun simctl list runtimes available で確認してください)" >&2
  exit 1
fi

# -l が区切り文字や空白だけ (-l ',' 等) だと対象言語が 0 件になり、完了判定が空ループで成功して 1 枚も撮らずに exit 0 になるため拒否する
if [ -n "$LANGUAGES" ] && [ -z "$(echo "$LANGUAGES" | tr ',' '\n' | tr -d ' ' | grep -v '^$')" ]; then
  echo "Error: -l に有効な言語が含まれていません: '$LANGUAGES'" >&2
  exit 1
fi

# ログファイルの設定
# fd 3 にコンソール出力を保存し、stdout/stderr はログファイルへリダイレクト
exec 3>&1 4>&2
LOG_DIR="$(pwd)/tmp"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/generate_appstore_screenshots.$(date +%Y%m%d_%H%M%S).logs.txt"
exec >"$LOG_FILE" 2>&1
echo "Log file: $LOG_FILE" >&3

# 進行ログを見やすく (コンソールとログファイルの両方に出す)
sep() {
  printf '\n==== %s ====\n' "$*"
  printf '==== %s ====\n' "$*" >&3
}

# スクリーンショット番号でテストファイルをフィルタリングする関数
# カンマ区切り（"1,2,3"）と範囲指定（"1-6"）の混在に対応
filter_test_files() {
  local numbers=$1
  local all_files=$2
  local filtered=""

  IFS=',' read -ra parts <<< "$numbers"
  for part in "${parts[@]}"; do
    if [[ "$part" == *-* ]]; then
      # 範囲指定（例: "1-6"）
      local start=${part%-*}
      local end=${part#*-}
      for ((i=start; i<=end; i++)); do
        local match
        match=$(echo "$all_files" | grep "AppStoreScreenshot${i}PageSnapshotUITest.swift" || true)
        [ -n "$match" ] && filtered+="$match"$'\n'
      done
    else
      # 単一番号
      local match
      match=$(echo "$all_files" | grep "AppStoreScreenshot${part}PageSnapshotUITest.swift" || true)
      [ -n "$match" ] && filtered+="$match"$'\n'
    fi
  done

  echo "$filtered" | sort -u | grep -v '^$'
}

# 対象言語リストを返す関数。未指定時の全言語は撮影言語の SSOT (AppStoreScreenshotsUITests/Languages.swift) から
# 読み取り、apply_variant.sh と同じ根拠で判定する (固定リストだと言語追加時に欠落を完了と誤判定する)
target_languages_list() {
  if [ -n "$LANGUAGES" ]; then
    echo "$LANGUAGES" | tr ',' '\n' | tr -d ' ' | grep -v '^$'
  else
    sed -n 's/^ *("\([^"]*\)",.*/\1/p' AppStoreScreenshotsUITests/Languages.swift
  fi
}

# テストのスクリーンショットが全言語分揃っているかチェックする関数
# 全ファイルが存在する場合は 0（true）を返す
is_test_complete() {
  local test_file=$1
  local filename=$(basename "$test_file" .swift)
  local screenshot_number=$(echo "$filename" | sed -E 's/AppStoreScreenshot([0-9]+)PageSnapshotUITest/\1/')
  local variant_name=$(get_variant_name "$screenshot_number")
  local variant_index=$(get_variant_index "$screenshot_number")
  local expected_file="${variant_index}_${SCREENSHOT_DISPLAY_TYPE}_${variant_index}.png"

  local lang
  for lang in $(target_languages_list); do
    local fastlane_lang=$(map_language_to_fastlane "$lang")
    local output_file="$VARIANT_OUTPUT_BASE_DIR/_variant-${variant_name}/${fastlane_lang}/${expected_file}"
    if [ ! -f "$output_file" ]; then
      return 1
    fi
  done
  return 0
}

# --overwrite 時に、対象テストの既存出力 (対象言語分) を削除する関数。
# 古い出力が残っていると、テストが失敗しても is_test_complete が前回の生成物で
# 成功と誤判定するため、実行前に消して今回の生成物だけで成否を判定できるようにする
remove_test_outputs() {
  local test_file=$1
  local filename=$(basename "$test_file" .swift)
  local screenshot_number=$(echo "$filename" | sed -E 's/AppStoreScreenshot([0-9]+)PageSnapshotUITest/\1/')
  local variant_name=$(get_variant_name "$screenshot_number")
  local variant_index=$(get_variant_index "$screenshot_number")
  local expected_file="${variant_index}_${SCREENSHOT_DISPLAY_TYPE}_${variant_index}.png"

  local lang
  for lang in $(target_languages_list); do
    local fastlane_lang=$(map_language_to_fastlane "$lang")
    rm -f "$VARIANT_OUTPUT_BASE_DIR/_variant-${variant_name}/${fastlane_lang}/${expected_file}"
  done
}

# 1つのテストを実行して抽出・整理する関数（並列実行の単位）
run_single_test() {
  local test_file=$1
  local test_count=$2
  local total_count=$3
  local temp_dir=$4

  sep "Processing test $test_count/$total_count: $test_file"

  # テスト実行パスと artifact パスを取得
  local test_path artifact_path
  read -r test_path artifact_path <<< "$(get_test_info "$test_file")"

  sep "Test path: $test_path"
  sep "Artifact path: $artifact_path"

  # テスト実行
  ./scripts/generate_screenshots/run_appstore_screenshot.sh "$test_path" "$artifact_path" "$LANGUAGES" || true

  # テスト実行直後にスクリーンショットを抽出・整理
  if [ -d "$artifact_path" ]; then
    sep "Extracting screenshots: $artifact_path"

    # テストごとにユニークな一時ディレクトリを使用（並列実行の競合回避）
    local test_temp_dir="${temp_dir}/$(basename "$test_file" .swift)"
    rm -rf "$test_temp_dir"
    mkdir -p "$test_temp_dir"

    # xcresulttool で Attachment を抽出
    xcrun xcresulttool export attachments \
      --path "$artifact_path" \
      --output-path "$test_temp_dir" || true

    # fastlane 形式に整理
    sep "Organizing screenshots to fastlane format"
    ./scripts/generate_screenshots/organize_appstore_screenshots.sh "$test_temp_dir" || true

    # 成功マーカーを作成（リトライ判定用）。
    # テストが失敗しても結果バンドル (artifact ディレクトリ) は作られるため、
    # ディレクトリの存在ではなく「対象言語分の出力が実際に揃ったか」で成功を判定する
    if is_test_complete "$test_file"; then
      touch "${temp_dir}/.success_${SCREENSHOT_DEVICE}_$(basename "$test_file" .swift)"
    fi

    # テストごとの一時ディレクトリを削除
    rm -rf "$test_temp_dir"
  else
    echo "Warning: Artifact not found: $artifact_path" >&3
  fi
}

# 一時ディレクトリの準備。前回の実行が途中で終わって残った成功マーカー (.success_*) を引き継ぐと、
# 今回の撮影が失敗してもリトライ・失敗報告をすり抜けて exit 0 になるため、開始時に作り直す
TEMP_SCREENSHOTS_DIR="scripts/generate_screenshots/temp_screenshots"
cleanup_temp_files
mkdir -p "$TEMP_SCREENSHOTS_DIR"

# 言語フィルタリング設定のログ出力
if [ -n "$LANGUAGES" ]; then
  sep "Languages: $LANGUAGES"
fi

# デバイス (表示サイズ) 一覧の検証。未対応の区分は撮影前に落とす
IFS=',' read -ra device_list <<< "$DEVICES"
device_list=($(printf '%s\n' "${device_list[@]}" | tr -d ' ' | grep -v '^$'))
if [ "${#device_list[@]}" -eq 0 ]; then
  echo "Error: -d に撮影デバイスが指定されていません" >&3
  exit 1
fi
for device in "${device_list[@]}"; do
  if ! get_display_type "$device" > /dev/null; then
    echo "Error: 未対応の撮影デバイスです: $device (対応: 69, 65)" >&3
    exit 1
  fi
done
# 専用シミュレータ名は 1 デバイス分にしか付けられない (別機種を同名では作れない) ため、複数デバイスとの併用は拒否する
if [ -n "${DESTINATION_SIM_NAME:-}" ] && [ "${#device_list[@]}" -gt 1 ]; then
  echo "Error: DESTINATION_SIM_NAME を使う時は -d で撮影デバイスを 1 つに絞ってください (指定: $DEVICES)" >&3
  exit 1
fi
sep "Devices: ${device_list[*]}"

# 最初のデバイスでシミュレータを用意してビルドする。
# build-for-testing の成果物は simulator SDK 共通で、他デバイスの test-without-building にもそのまま使える
configure_screenshot_device "${device_list[0]}"

# シミュレータが存在しない場合は自動作成
ensure_simulator_exists

# ビルド
if [ "$SKIP_BUILD" = false ]; then
  rm -rf artifacts/appstore_screenshots
  sep "Building AppStore Screenshot Tests"
  ./scripts/generate_screenshots/build_appstore_screenshot.sh
else
  sep "Skipping build (--skip-build specified)"
fi

# AppStoreScreenshot テストファイルのみを検索
sep "Collecting AppStore screenshot test files"
test_files=$(find AppStoreScreenshotsUITests/Features/AppStoreScreenshot \
  -type f -name "*SnapshotUITest.swift" 2>/dev/null | sort)

if [ -z "$test_files" ]; then
  echo "Error: No AppStoreScreenshot test files found in AppStoreScreenshotsUITests/Features/AppStoreScreenshot/" >&3
  exit 1
fi

# -n オプションが指定されていればフィルタリング
if [ -n "$SCREENSHOT_NUMBERS" ]; then
  sep "Filtering by screenshot numbers: $SCREENSHOT_NUMBERS"
  test_files=$(filter_test_files "$SCREENSHOT_NUMBERS" "$test_files")

  if [ -z "$test_files" ]; then
    echo "Error: No test files match the specified numbers: $SCREENSHOT_NUMBERS" >&3
    exit 1
  fi
fi

total_count=$(echo "$test_files" | wc -l | tr -d ' ')
sep "Found $total_count AppStore screenshot test(s), running with $PARALLEL parallel job(s)"

# 1 デバイス分の全テスト実行 (並列実行 → 失敗分の逐次リトライ) を行う関数。
# 成否は成功マーカー (.success_{device}_{test}) で記録し、最後にデバイス横断で集計する
run_all_tests_for_device() {
  local device=$1
  configure_screenshot_device "$device"
  sep "Device: $device ($SCREENSHOT_DEVICE_TYPE, $SCREENSHOT_DISPLAY_TYPE)"

  # シミュレータが存在しない場合は自動作成 (2 台目以降のデバイスはここで用意する)
  ensure_simulator_exists

  # 並列実行ループ
  # 並列数の制御は PID を FIFO で待つ方式にする (macOS 標準の Bash 3.2 には wait -n が無く、
  # `wait -n || true` は失敗が握り潰されて実際には待機しないため)
  job_pids=()
  test_count=0
  for test_file in $test_files; do
    test_count=$((test_count + 1))

    # --overwrite の場合は既存出力を先に削除し、今回の生成物だけで成否を判定する
    if [ "$OVERWRITE" = true ]; then
      remove_test_outputs "$test_file"
    fi

    # --overwrite でない場合、全言語分のファイルが揃っていればスキップ
    if [ "$OVERWRITE" = false ] && is_test_complete "$test_file"; then
      sep "Skipping test $test_count/$total_count (already complete): $(basename "$test_file")"
      continue
    fi

    run_single_test "$test_file" "$test_count" "$total_count" "$TEMP_SCREENSHOTS_DIR" &
    job_pids+=($!)

    # 並列数上限に達したら最も古いジョブの完了を待つ
    if [ "${#job_pids[@]}" -ge "$PARALLEL" ]; then
      wait "${job_pids[0]}" 2>/dev/null || true
      job_pids=(${job_pids[@]+"${job_pids[@]:1}"})
    fi
  done

  # 残りのバックグラウンドジョブ完了を待つ
  wait 2>/dev/null || true

  # 失敗テストの検出とリトライ
  failed_tests=""
  for test_file in $test_files; do
    marker="${TEMP_SCREENSHOTS_DIR}/.success_${SCREENSHOT_DEVICE}_$(basename "$test_file" .swift)"
    if [ ! -f "$marker" ]; then
      failed_tests+="$test_file"$'\n'
    fi
  done
  failed_tests=$(echo "$failed_tests" | grep -v '^$' || true)

  if [ -n "$failed_tests" ]; then
    failed_count=$(echo "$failed_tests" | wc -l | tr -d ' ')
    sep "Retrying $failed_count failed test(s) sequentially"

    retry_count=0
    for test_file in $failed_tests; do
      retry_count=$((retry_count + 1))

      # リトライ前にもう一度チェック（他のテストの副作用等で揃っている可能性）
      if [ "$OVERWRITE" = false ] && is_test_complete "$test_file"; then
        sep "Skipping retry $retry_count/$failed_count (already complete): $(basename "$test_file")"
        # リトライ不要なのでsuccessマーカーを作成
        touch "${TEMP_SCREENSHOTS_DIR}/.success_${SCREENSHOT_DEVICE}_$(basename "$test_file" .swift)"
        continue
      fi

      run_single_test "$test_file" "$retry_count" "$failed_count" "$TEMP_SCREENSHOTS_DIR"
    done
  fi
}

for device in "${device_list[@]}"; do
  run_all_tests_for_device "$device"
done

# 最終的な失敗テストの確認 (全デバイス横断)
final_failed=""
for device in "${device_list[@]}"; do
  for test_file in $test_files; do
    marker="${TEMP_SCREENSHOTS_DIR}/.success_${device}_$(basename "$test_file" .swift)"
    if [ ! -f "$marker" ]; then
      final_failed+="  - [$device] $(basename "$test_file")"$'\n'
    fi
  done
done

# 一時ファイル・ディレクトリの最終クリーンアップ
cleanup_temp_files

# リトライ後も出力が揃わなかったテストがある場合は、欠落した一式を正常な素材として
# 後続処理 (apply_variant / fastlane) に渡さないよう非ゼロで終了する
if [ -n "$final_failed" ]; then
  sep "ERROR: The following tests failed even after retry:"
  echo "$final_failed" >&3
  echo "$final_failed"
  echo "ログファイル: $LOG_FILE" >&3
  exit 1
fi

sep "All done."
sep "App Store screenshots saved to: $VARIANT_OUTPUT_BASE_DIR/_variant-*/"
echo ""
echo "" >&3
echo "利用可能なバリアント:"
echo "利用可能なバリアント:" >&3
ls -d "$VARIANT_OUTPUT_BASE_DIR"/_variant-* 2>/dev/null | sed 's|.*/_variant-||' | while read v; do
  echo "  - $v"
  echo "  - $v" >&3
done
echo ""
echo "" >&3
echo "選択バリアントを適用:"
echo "選択バリアントを適用:" >&3
echo "  ./scripts/generate_screenshots/apply_variant.sh <variant-name>"
echo "  ./scripts/generate_screenshots/apply_variant.sh <variant-name>" >&3
echo ""
echo "" >&3
echo "ログファイル: $LOG_FILE"
echo "ログファイル: $LOG_FILE" >&3
