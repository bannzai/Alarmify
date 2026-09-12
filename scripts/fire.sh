#!/usr/bin/env bash
set -euo pipefail

# 対話入力のたびに新しいアラームを作るテスト用コマンドのため、登録は非冪等。
# 更新・キャンセルは入力した既存 ID を使う。通信失敗時の自動再送はしない。
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '使い方: ./scripts/fire.sh <APIトークン>\n引数を省略するとトークンを非表示で入力できます\n必要なコマンド: curl, jq\nAPI仕様: docs/api.md\n'
  exit 0
fi
if (( $# > 1 )); then
  printf 'エラー: 引数はAPIトークン1つだけ指定してください\n' >&2
  exit 1
fi
for command in curl jq; do
  if ! command -v "$command" >/dev/null; then
    printf 'エラー: %s が必要です\n' "$command" >&2
    exit 1
  fi
done
token=${1:-}
if [[ -z $token ]]; then
  read -r -s -p 'APIトークン: ' token
  printf '\n' >&2
fi
if [[ -z $token || $token == *$'\n'* || $token == *$'\r'* ]]; then
  printf 'エラー: 空または改行を含むトークンは使えません\n' >&2
  exit 1
fi

printf '%s\n' '1) 最短で鳴らす（約30秒後）' '2) 1分後に鳴らす' '3) 秒数を指定して鳴らす' '4) 既存アラームの時刻・タイトルを更新する' '5) 既存アラームをキャンセルする' '0) 終了'
read -r -p 'ユースケース: ' choice
case "$choice" in
  0) exit 0 ;;
  1) seconds=0 ;;
  2) seconds=60 ;;
  3|4)
    read -r -p '何秒後に鳴らすか（0〜31536000、30未満は30秒後）: ' seconds
    if [[ ! $seconds =~ ^[0-9]{1,8}$ ]] || (( 10#$seconds > 31536000 )); then
      printf 'エラー: 秒数は0〜31536000の整数で指定してください\n' >&2
      exit 1
    fi
    seconds=$((10#$seconds))
    ;;
  5) ;;
  *) printf 'エラー: メニューの番号を指定してください\n' >&2; exit 1 ;;
esac
id=''
if [[ $choice == 4 || $choice == 5 ]]; then
  read -r -p 'アラームID（登録時のレスポンスのid）: ' id
  if [[ ! $id =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    printf 'エラー: アラームIDはUUIDで指定してください\n' >&2
    exit 1
  fi
fi
if [[ $choice == 5 ]]; then
  url="https://api.signalarm.app/v1/alarms/$id"
  request_args=(--request DELETE)
else
  read -r -p 'タイトル（空欄ならAPI既定のSignalarm）: ' title
  body=$(jq -nc --argjson seconds "$seconds" --arg title "$title" --arg id "$id" \
    '{fire_in: $seconds} + (if $title == "" then {} else {title: $title} end) + (if $id == "" then {} else {id: $id} end)')
  url=https://api.signalarm.app/v1/alarms
  request_args=(--request POST --data-raw "$body")
fi
# ヘッダーを標準入力から渡し、curl のプロセス引数にトークンを載せない。
# 成功レスポンスは端末上での登録・発火を保証しないため、実機での確認に使う。
printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$token" |
  curl --silent --show-error --fail-with-body --connect-timeout 10 --max-time 30 \
    --header @- "${request_args[@]}" "$url"
printf '\n'
