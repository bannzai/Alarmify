#!/bin/bash
#
# simulator_common.sh
#
# スクリーンショット生成系スクリプト (generate_screenshots / snapshot_ui_tests) が共有する
# シミュレータ関連の共通関数。各 env スクリプトから source して使用する。
#

# インストール済みランタイムから、指定したメジャーバージョン系列の iOS 実バージョンを解決する関数。
# Xcode の更新でランタイムの実バージョンは 26.0 → 26.0.1 のように進み、xcodebuild の destination の
# OS= は実バージョンでしか一致しない (マーケティング名 26.0 のままでは destination 不一致で失敗する)
# ため、固定値ではなく実行時に解決する。
# 複数ある場合は最も低いバージョンを返す (iOS 26.5 の simulator は StoreKit Testing が機能しない
# 実測があるため、最新ではなく最低に寄せる。CLAUDE.md「検証方法」)
# Usage: resolve_ios_runtime_version <メジャーバージョン (例: 26)>
resolve_ios_runtime_version() {
  # ランタイム一覧の行形式: "iOS 26.0 (26.0.1 - 23A8464) - com.apple.CoreSimulator.SimRuntime.iOS-26-0"
  # 利用不可 ((unavailable, ...) 付き) の古いランタイムを拾わないよう available で絞る。
  # xcrun 自体が無い環境 (Xcode 未導入で source された場合) でも呼び出し元の set -e を
  # 壊さないよう、失敗は空文字として返し、必須チェックは撮影を行うスクリプト側で行う
  { xcrun simctl list runtimes available 2>/dev/null || true; } | sed -nE "s/^iOS $1(\.[0-9.]+)? \(([0-9.]+) - .*/\2/p" | sort -V | head -1
}

# DESTINATIONで指定されたシミュレータが存在しない場合に自動作成する関数
# DESTINATIONからシミュレータ名とOSバージョンを抽出し、
# xcrun simctl を使ってシミュレータの存在確認・作成を行う
ensure_simulator_exists() {
  local sim_name
  sim_name=$(echo "$DESTINATION" | sed -E 's/.*name=([^,]+).*/\1/')
  local os_version
  os_version=$(echo "$DESTINATION" | sed -E 's/.*OS=([^,]+).*/\1/')

  # DESTINATION の OS は実バージョン (26.0.1)、simctl のデバイス一覧の見出しはマーケティング名 (iOS 26.0) で
  # 齟齬があるため、ランタイム一覧の行を先に特定してマーケティング名とランタイムIDの両方をそこから取る。
  # 実バージョン・マーケティング名のどちらを渡されても行を特定できるようにする (バージョン一致は
  # 行頭のマーケティング名か括弧内の実バージョンのどちらかに一致すればよい)
  # 利用不可ランタイムに一致させない (available で絞る)。呼び出し元の set -e / pipefail で
  # grep の不一致 (exit 1) が即時終了にならないよう、不一致は空文字に落とす
  local runtime_line
  runtime_line=$(xcrun simctl list runtimes available | { grep -E "^iOS ${os_version} \(|\(${os_version} - " || true; } | head -1)

  if [ -z "$runtime_line" ]; then
    echo "エラー: iOS ${os_version} ランタイムが見つかりません。" >&2
    echo "利用可能なランタイム:" >&2
    xcrun simctl list runtimes | grep "iOS" >&2
    return 1
  fi

  local os_marketing_version
  os_marketing_version=$(echo "$runtime_line" | sed -E 's/^iOS ([0-9.]+) .*/\1/')

  echo "シミュレータ確認: name=${sim_name}, OS=${os_version} (iOS ${os_marketing_version})"

  # 該当シミュレータが存在するか確認。
  # 同名デバイスが別の iOS ランタイムにだけ存在するケースを「存在する」と誤判定しないよう、
  # simctl の検索語で対象 OS のランタイム区分に絞ってから名前を照合する。
  # grep -q は最初のマッチで早期終了し、出力の多い環境では simctl 側が SIGPIPE で非0終了する。
  # 呼び出し元スクリプトが set -o pipefail のためパイプ全体が失敗扱いになり、
  # 既存シミュレータを「存在しない」と誤判定して重複作成してしまうので -q は使わない
  if xcrun simctl list devices "iOS ${os_marketing_version}" | grep "${sim_name} (" > /dev/null; then
    echo "シミュレータ '${sim_name}' は既に存在します。作成をスキップします。"
    return 0
  fi

  echo "シミュレータ '${sim_name}' が見つかりません。自動作成します。"

  # デバイスタイプIDを取得
  # DESTINATION_SIM_NAME で「issue-13-13PM」のような専用名を使う場合、
  # 専用名はデバイスタイプ名と一致しないため、検索には DESTINATION_SIM_DEVICE_TYPE
  # (未指定時は iPhone 13 Pro Max) を使う。スペースをハイフンに変換して検索する
  local device_type_name="${DESTINATION_SIM_DEVICE_TYPE:-iPhone 13 Pro Max}"
  local device_type_search
  device_type_search=$(echo "$device_type_name" | tr ' ' '-')
  local device_type_id
  device_type_id=$(xcrun simctl list devicetypes | grep -i "$device_type_search" | head -1 | sed -E 's/.*\(([^)]+)\).*/\1/')

  if [ -z "$device_type_id" ]; then
    echo "エラー: デバイスタイプ '${device_type_name}' が見つかりません。" >&2
    echo "利用可能なデバイスタイプ:" >&2
    xcrun simctl list devicetypes | grep -i "iPhone" >&2
    return 1
  fi
  echo "デバイスタイプID: ${device_type_id}"

  # ランタイムIDを取得 (存在確認で特定済みのランタイム行の末尾フィールド)
  local runtime_id
  runtime_id=$(echo "$runtime_line" | awk '{print $NF}')
  echo "ランタイムID: ${runtime_id}"

  # シミュレータを作成
  echo "シミュレータを作成中: xcrun simctl create \"${sim_name}\" ${device_type_id} ${runtime_id}"
  xcrun simctl create "${sim_name}" "${device_type_id}" "${runtime_id}"

  echo "シミュレータ '${sim_name}' を作成しました。"
}
