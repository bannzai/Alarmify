#!/usr/bin/env bash
#
# generate_duo_screenshots.sh
#
# 【どのようなスクリプトか】
# 折りたたみ端末 iPhone Duo 用の App Store スクリーンショット (外側ディスプレイ・内側ディスプレイ) を、
# 既存の AppStoreScreenshot の UITest を iPhone Duo の simulator で動かして生成する。
# 作り方は appstore-screenshot-builder skill の references/iphone-duo.md (SwiftUI の節) に従う
# (取り込み元: bannzai/Focus の同名スクリプト)。
#
#   1. iPhone Duo の simulator を用意する (sim-boot。DUO_SIM_UDID を渡せばその simulator を使う)
#   2. UITest をビルドする (build_appstore_screenshot.sh)
#   3. 閉じた姿勢 (外側ディスプレイ) で UITest を実行し、XCTAttachment の画像を {言語}/outer/{インデックス}.png にする
#   4. 開いた姿勢 (内側ディスプレイ) で UITest を実行し、テストがページを表示するたびに
#      ホスト側で `xcrun simctl io <UDID> screenshot --display=primary-1` を撮って {言語}/inner/{インデックス}.png にする
#      (内側は XCTest の API では仕様の寸法で撮れないため。テストとの同期は
#       AppStoreScreenshotsUITests/XCTestCase+AppStoreScreenshot.swift の attachAppStoreScreenshot を参照)
#   5. alpha を落とし、verify_duo_screenshots.sh で寸法・alpha・枚数を機械検証する
#   6. simulator を閉じた姿勢に戻す (simulator の停止は呼び出し側で `sim-shutdown "$(sim-id)"` を行う)
#
# 内側ディスプレイは横向き (2853×2007 px) で作る。開いた姿勢の simulator は向きが landscapeRight になり、
# simctl が回転なしで 2853×2007 を返すため (references/iphone-duo.md「決めること」)。
#
# 出力先は fastlane deliver が読まない scripts/generate_screenshots/artifacts/_duo/_variant-{名前}/{言語}/。
# deliver は画像の px 寸法で表示クラスを判定し、Duo の寸法を受け付けず、
# fastlane/screenshots/ に置くとアップロード全体が止まるため (references/iphone-duo.md「アップロード経路」)。
# App Store Connect へ上げる手順は scripts/generate_screenshots/README.md。
#
# 【使い方】
#   全言語・全ページ (1-5) で生成:
#   $ ./scripts/generate_screenshots/generate_duo_screenshots.sh
#
#   言語・ページを絞る:
#   $ ./scripts/generate_screenshots/generate_duo_screenshots.sh -l "ja" -n "1,2"
#
#   ビルドを省略する / 片方のディスプレイだけ撮る:
#   $ ./scripts/generate_screenshots/generate_duo_screenshots.sh --skip-build --display inner
#
# オプション:
#   -l LANGS              言語のカンマ区切り (既定: AppStoreScreenshotsUITests/Languages.swift の全言語)
#   -n NUMS               スクリーンショット番号 (例: "1-5" / "1,3")。既定は 1-5
#   --display DISPLAY     outer / inner / both (既定: both)
#   --skip-build          build-for-testing を省略する
#
# 環境変数:
#   DUO_SIM_UDID   使う iPhone Duo の simulator の UDID。未指定なら `SIM_DEVICE_TYPE="iPhone Duo" sim-boot` で用意する
#   DUO_POSE_SH    姿勢を切り替えるスクリプト (既定: ~/.claude/skills/ios-simulator/scripts/duo-pose.sh)
#
# 前提:
#   - Xcode 27.1 以降と iOS 27.1 以降のランタイム (iPhone Duo の simulator はそれ以降にしか無い)
#   - sim-boot (DUO_SIM_UDID を渡さない時)、ImageMagick (magick)、jq
#   - duo-pose.sh が Device Hub のウィンドウをアクセシビリティ API で操作するため、ローカルの Mac で実行する
#     (リモートの simulator では姿勢を切り替えられない)
#   - 撮れるのは、UITest が attachAppStoreScreenshot で撮影しているページだけ。
#     ページを追加する時は、その UITest も attachAppStoreScreenshot で撮影する
#
# 【終了コード】
#   0: 生成と機械検証がすべて成功
#   1: 失敗 (機械検証の NG を含む)
#   2: 引数不正
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT_DIR="$SCRIPT_DIR/../.."
cd "$PROJECT_ROOT_DIR"

source scripts/generate_screenshots/appstore_screenshot_env.sh

SCREENSHOT_NUMBERS="1-5"
# 既定の言語は撮影言語の SSOT (Languages.swift) から読む (generate_appstore_screenshots.sh と同じ根拠)
LANGUAGES=$(sed -n 's/^ *("\([^"]*\)",.*/\1/p' AppStoreScreenshotsUITests/Languages.swift | paste -sd, -)
DISPLAY_TARGET="both"
SKIP_BUILD=false
DUO_POSE_SH="${DUO_POSE_SH:-$HOME/.claude/skills/ios-simulator/scripts/duo-pose.sh}"

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
    --display)
      DISPLAY_TARGET="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      sed -n '2,60p' "$0" | sed -E 's/^# ?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$DISPLAY_TARGET" != "outer" && "$DISPLAY_TARGET" != "inner" && "$DISPLAY_TARGET" != "both" ]]; then
  echo "Error: --display は outer / inner / both のどれかを指定してください: $DISPLAY_TARGET" >&2
  exit 2
fi

# "1-3,5" のような番号指定を 1 行 1 番号に展開する
expand_numbers() {
  local part
  IFS=',' read -ra parts <<< "$1"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      echo "$part"
    else
      echo "Error: 番号として解釈できません: $part" >&2
      return 2
    fi
  done
}
numbers=$(expand_numbers "$SCREENSHOT_NUMBERS")

# バリアントをまたぐ指定は出力先が分かれて検証しづらいため、1 回の実行は 1 バリアントに限る
variant_name=$(get_variant_name "$(echo "$numbers" | head -1)")
for number in $numbers; do
  if [ "$(get_variant_name "$number")" != "$variant_name" ]; then
    echo "Error: 1 回の実行で指定できるのは 1 つのバリアントの番号だけです: $SCREENSHOT_NUMBERS" >&2
    exit 2
  fi
  if ! grep -q "attachAppStoreScreenshot" "AppStoreScreenshotsUITests/Features/AppStoreScreenshot/AppStoreScreenshot${number}PageSnapshotUITest.swift"; then
    echo "Error: AppStoreScreenshot${number}PageSnapshotUITest が attachAppStoreScreenshot で撮影していないため、内側ディスプレイを撮れません" >&2
    exit 2
  fi
done

OUTPUT_DIR="$VARIANT_OUTPUT_BASE_DIR/_duo/_variant-${variant_name}"
WORK_DIR="$(pwd)/artifacts/appstore_screenshots/duo"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

# simulator を用意する
if [ -z "${DUO_SIM_UDID:-}" ]; then
  echo "==== iPhone Duo の simulator を用意します (sim-boot) ===="
  DUO_SIM_UDID=$(SCRIPT_QUIET=1 SIM_DEVICE_TYPE="iPhone Duo" sim-boot | sed -n 's/^DEVICE_UDID=//p' | tail -1)
fi
if [ -z "$DUO_SIM_UDID" ]; then
  echo "Error: iPhone Duo の simulator の UDID を取得できませんでした" >&2
  exit 1
fi
export DESTINATION_SIM_UDID="$DUO_SIM_UDID"
source scripts/generate_screenshots/appstore_screenshot_env.sh
echo "==== simulator: $DUO_SIM_UDID ===="

# 姿勢を切り替える。起動直後は有効なディスプレイを判定できず STATUS=ERROR になることがあるため、
# 間をおいて再試行する (references/iphone-duo.md の SwiftUI の節 3 番)
set_pose() {
  local pose=$1
  local attempt
  for attempt in 1 2 3 4 5; do
    if bash "$DUO_POSE_SH" set --udid "$DUO_SIM_UDID" "$pose"; then
      # 切り替えの直後は描画が追いつかないことがあるため、少し待ってから撮る (ios-simulator skill Phase 2)
      sleep 5
      return 0
    fi
    echo "姿勢の切り替えに失敗しました (${attempt} 回目)。待ってから再試行します" >&2
    sleep 5
  done
  echo "Error: 姿勢を ${pose} に切り替えられませんでした" >&2
  return 1
}

# 終了時は外側ディスプレイ (閉じた姿勢) に戻す
trap 'bash "$DUO_POSE_SH" set --udid "$DUO_SIM_UDID" closed > /dev/null 2>&1 || true' EXIT

if [ "$SKIP_BUILD" = false ]; then
  ./scripts/generate_screenshots/build_appstore_screenshot.sh
fi

# UITest の attachment 名 ({class}---{function}---{language}---{index}) から、
# 出力先のパス ({出力先}/{fastlane の言語}/{outer|inner}/{バリアント内インデックス}.png) を返す
output_path_for_attachment() {
  local attachment_name=$1
  local display=$2
  local language test_class screenshot_number variant_index
  language=$(echo "$attachment_name" | awk -F'---' '{print $3}')
  test_class=$(echo "$attachment_name" | awk -F'---' '{print $1}')
  screenshot_number=$(echo "$test_class" | sed -E 's/AppStoreScreenshot([0-9]+)PageSnapshotUITest/\1/')
  variant_index=$(get_variant_index "$screenshot_number")
  echo "$OUTPUT_DIR/$(map_language_to_fastlane "$language")/${display}/${variant_index}.png"
}

# alpha を落として出力先に置く (simctl の画像は hasAlpha: yes になり、App Store は alpha 付きを受け付けないため)
place_png() {
  local source=$1
  local destination=$2
  mkdir -p "$(dirname "$destination")"
  magick "$source" -alpha remove -alpha off "$destination"
  echo "Placed: $destination"
}

# 撮影に失敗したページ ({outer|inner}:{番号})。失敗しても他のページの撮影を続け、最後に 1 つでもあれば exit 1 にする
failed_pages=()

# 今回撮る言語・ページの前回の画像を消す。
# 撮影に失敗したページを前回の画像で補ったまま機械検証を通さないため
# 引数: $1 outer / inner
remove_previous_outputs() {
  local display=$1
  local language number
  for language in $(echo "$LANGUAGES" | tr ',' ' '); do
    for number in $numbers; do
      rm -f "$OUTPUT_DIR/$(map_language_to_fastlane "$language")/${display}/$(get_variant_index "$number").png"
    done
  done
}

# 外側ディスプレイ: 閉じた姿勢で UITest を実行し、XCTAttachment の画像を置く
generate_outer() {
  set_pose closed
  remove_previous_outputs outer
  local number test_path artifact_path export_dir
  for number in $numbers; do
    read -r test_path artifact_path <<< "$(get_test_info "AppStoreScreenshot${number}PageSnapshotUITest.swift")"
    artifact_path="$WORK_DIR/outer/$(basename "$(dirname "$artifact_path")")"
    if ! PARALLEL_TESTING_ENABLED=NO ./scripts/generate_screenshots/run_appstore_screenshot.sh "$test_path" "$artifact_path" "$LANGUAGES"; then
      failed_pages+=("outer:$number")
    fi

    export_dir="$WORK_DIR/outer-export/$number"
    rm -rf "$export_dir"
    mkdir -p "$export_dir"
    # テストが一部の言語で失敗しても、撮れた言語の画像は置く
    if ! xcrun xcresulttool export attachments --path "$artifact_path" --output-path "$export_dir"; then
      echo "Warning: attachment を取り出せませんでした: $artifact_path" >&2
      failed_pages+=("outer:$number")
      continue
    fi
    jq -r '.[] | .attachments[] | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' "$export_dir/manifest.json" |
      while IFS=$'\t' read -r exported_file suggested_name; do
        place_png "$export_dir/$exported_file" "$(output_path_for_attachment "${suggested_name%.png}" outer)"
      done
  done
}

# 内側ディスプレイを、ホームインジケーターが写っていない状態で撮る。
# UITest のタップで再表示されたホームインジケーターは persistentSystemOverlays(.hidden) で数秒後に消えるが、
# 消えるまでの時間が一定でなく、撮ってから写っていれば待って撮り直す (写った率は 10 枚中 2〜3 枚、最大 5 回)。
# 写っているかは、インジケーターの位置 (下端中央の幅 760px・高さ 30px) の平均輝度で判定する。
# しきい値 0.07 は、写った画像が 0.10、写っていない画像が 0.04 だった実測の中間
capture_inner_without_home_indicator() {
  local destination="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    xcrun simctl io "$DUO_SIM_UDID" screenshot --display=primary-1 "$destination" > /dev/null
    # simctl の PNG は alpha 付きで、alpha を残したまま輝度を取ると透明な画素が明るく数えられるため、place_png と同じく落としてから測る
    if [ "$(magick "$destination" -alpha remove -alpha off -crop 760x30+1046+1970 +repage -colorspace Gray -format '%[fx:mean < 0.07 ? 1 : 0]' info:)" = "1" ]; then
      return 0
    fi
    echo "ホームインジケーターが写ったため撮り直します ($attempt 回目): $destination" >&2
    sleep 3
  done
  echo "Error: ホームインジケーターが消えないため撮れませんでした: $destination" >&2
  return 1
}

# 内側ディスプレイ: 開いた姿勢で UITest を実行し、テストが書く {name}.ready を見てホスト側で撮る
generate_inner() {
  set_pose open
  remove_previous_outputs inner
  local capture_dir="$WORK_DIR/inner-capture"
  local number test_path artifact_path capture_loop_pid
  for number in $numbers; do
    rm -rf "$capture_dir"
    mkdir -p "$capture_dir"

    # テストの {name}.ready を待って内側ディスプレイを撮り、{name}.done で撮り終えたことをテストに伝える
    (
      capture_failed=0
      while [ ! -e "$capture_dir/.stop" ]; do
        for ready_file in "$capture_dir"/*.ready; do
          if [ -e "$ready_file" ]; then
            name=$(basename "$ready_file" .ready)
            # 撮れなくても .done は書く (テストを 120 秒の timeout まで待たせないため)。失敗はこのループの終了コードで伝える
            if capture_inner_without_home_indicator "$capture_dir/$name.png"; then
              place_png "$capture_dir/$name.png" "$(output_path_for_attachment "$name" inner)"
            else
              capture_failed=1
            fi
            mv "$ready_file" "$capture_dir/$name.taken"
            touch "$capture_dir/$name.done"
          fi
        done
        sleep 0.2
      done
      exit "$capture_failed"
    ) &
    capture_loop_pid=$!

    read -r test_path artifact_path <<< "$(get_test_info "AppStoreScreenshot${number}PageSnapshotUITest.swift")"
    artifact_path="$WORK_DIR/inner/$(basename "$(dirname "$artifact_path")")"
    if ! TEST_RUNNER_SNAPSHOT_HOST_CAPTURE_DIR="$capture_dir" PARALLEL_TESTING_ENABLED=NO \
      ./scripts/generate_screenshots/run_appstore_screenshot.sh "$test_path" "$artifact_path" "$LANGUAGES"; then
      failed_pages+=("inner:$number")
    fi

    touch "$capture_dir/.stop"
    if ! wait "$capture_loop_pid"; then
      failed_pages+=("inner:$number")
    fi
  done
}

if [ "$DISPLAY_TARGET" != "inner" ]; then
  generate_outer
fi
if [ "$DISPLAY_TARGET" != "outer" ]; then
  generate_inner
fi

# 機械検証は両方のディスプレイが揃う --display both の時だけ行う
if [ "$DISPLAY_TARGET" = "both" ]; then
  fastlane_languages=$(echo "$LANGUAGES" | tr ',' '\n' | while read -r language; do map_language_to_fastlane "$language"; done | paste -sd, -)
  variant_indices=$(for number in $numbers; do get_variant_index "$number"; done | paste -sd, -)
  ./scripts/generate_screenshots/verify_duo_screenshots.sh "$OUTPUT_DIR" "$fastlane_languages" "$variant_indices"
fi

echo "==== 出力先: $(pwd)/$OUTPUT_DIR ===="

if [ "${#failed_pages[@]}" -gt 0 ]; then
  echo "Error: 撮影に失敗したページがあります: ${failed_pages[*]}" >&2
  exit 1
fi
