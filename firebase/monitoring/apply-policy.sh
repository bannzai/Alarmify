#!/bin/bash
# Cloud Monitoring のアラートポリシーを JSON 定義から適用する (冪等)。
# 同じ displayName のポリシーが無ければ作成し、あれば同じ name を保って update する。
# 対象プロジェクトは定義ファイルの notificationChannels (projects/<PROJECT_ID>/notificationChannels/...)
# から決める。通知チャンネルはポリシーと同じプロジェクトのものしか使えないため、別のプロジェクトを指定する引数は持たない。
#
# 使い方: bash firebase/monitoring/apply-policy.sh <policy.json>
set -euo pipefail

POLICY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      [[ -z "$POLICY_FILE" ]] || { echo "ERROR: 不明な引数: $1" >&2; exit 2; }
      POLICY_FILE="$1"; shift ;;
  esac
done
[[ -n "$POLICY_FILE" ]] || { echo "ERROR: ポリシー定義ファイルを指定してください" >&2; exit 2; }
[[ -f "$POLICY_FILE" ]] || { echo "ERROR: $POLICY_FILE がありません" >&2; exit 2; }

DISPLAY_NAME="$(jq -r '.displayName // empty' "$POLICY_FILE")"
[[ -n "$DISPLAY_NAME" ]] || { echo "ERROR: $POLICY_FILE に displayName がありません" >&2; exit 2; }

# 通知チャンネルの projects/<id>/ からプロジェクトを決める。複数のプロジェクトが混ざる定義は Monitoring API が拒否するため先に止める
PROJECTS="$(jq -r '[.notificationChannels[]? | capture("^projects/(?<p>[^/]+)/notificationChannels/") | .p] | unique | .[]' "$POLICY_FILE")"
if [[ -z "$PROJECTS" ]]; then
  echo "ERROR: $POLICY_FILE の notificationChannels が空か、projects/<PROJECT_ID>/notificationChannels/... の形式ではありません" >&2
  exit 2
fi
if [[ "$(wc -l <<<"$PROJECTS")" -ne 1 ]]; then
  echo "ERROR: $POLICY_FILE の notificationChannels が複数のプロジェクトを参照しています (1 つのプロジェクトに揃えてください):" >&2
  echo "$PROJECTS" >&2
  exit 2
fi
PROJECT="$PROJECTS"

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
