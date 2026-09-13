#!/bin/bash
# Cloud Monitoring のアラートポリシーを JSON 定義から適用する (冪等)。
# 同じ displayName のポリシーが無ければ作成し、あれば同じ name を保って update する。
#
# 使い方: bash firebase/monitoring/apply-policy.sh <policy.json> [--project <PROJECT_ID>]
#   --project の既定は alarmify-prod (定義ファイルの通知チャンネルがこのプロジェクトのものであるため)
set -euo pipefail

POLICY_FILE=""
PROJECT="alarmify-prod"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR: --project に値が必要です" >&2; exit 2; }
      PROJECT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      [[ -z "$POLICY_FILE" ]] || { echo "ERROR: 不明な引数: $1" >&2; exit 2; }
      POLICY_FILE="$1"; shift ;;
  esac
done
[[ -n "$POLICY_FILE" ]] || { echo "ERROR: ポリシー定義ファイルを指定してください" >&2; exit 2; }
[[ -f "$POLICY_FILE" ]] || { echo "ERROR: $POLICY_FILE がありません" >&2; exit 2; }

DISPLAY_NAME="$(jq -r '.displayName // empty' "$POLICY_FILE")"
[[ -n "$DISPLAY_NAME" ]] || { echo "ERROR: $POLICY_FILE に displayName がありません" >&2; exit 2; }

EXISTING="$(gcloud alpha monitoring policies list --project="$PROJECT" \
  --filter="displayName=\"$DISPLAY_NAME\"" --format='value(name)')"

if [[ -z "$EXISTING" ]]; then
  echo "作成: $DISPLAY_NAME ($PROJECT)"
  gcloud alpha monitoring policies create --project="$PROJECT" --policy-from-file="$POLICY_FILE"
else
  if [[ "$(wc -l <<<"$EXISTING")" -ne 1 ]]; then
    echo "ERROR: displayName '$DISPLAY_NAME' のポリシーが複数あります。手で 1 つに整理してから再実行してください:" >&2
    echo "$EXISTING" >&2
    exit 1
  fi
  echo "更新: $DISPLAY_NAME ($EXISTING)"
  gcloud alpha monitoring policies update "$EXISTING" --project="$PROJECT" --policy-from-file="$POLICY_FILE"
fi
