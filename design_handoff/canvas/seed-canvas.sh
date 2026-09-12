#!/usr/bin/env bash
# design_handoff/canvas の作業ファイルからデザインカンバスのページを組み立てて検査する (冪等: 出力を毎回作り直す)。
# DESIGN_SKILL_DIR に Claude Code の /design skill の base directory (seed-canvas.mjs と payload.template.html がある場所) を渡す。
# 出力先は OUT (既定: <リポジトリ>/tmp/signalarm-screens.html。約 2 MB のためリポジトリにはコミットしない)
set -u
: "${DESIGN_SKILL_DIR:?set DESIGN_SKILL_DIR to the /design skill base directory}"
CANVAS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CANVAS/../.." && pwd)"
OUT="${OUT:-$ROOT/tmp/signalarm-screens.html}"
mkdir -p "$(dirname "$OUT")"
cd "$CANVAS" || exit 1
args=()
while read -r f; do
  args+=(--artboard "$f")
done < "$CANVAS/files.txt"
node "$DESIGN_SKILL_DIR/seed-canvas.mjs" --template "$DESIGN_SKILL_DIR/payload.template.html" --out "$OUT" --title "Signalarm Screens" "${args[@]}" --canvas canvas.json || exit 1
node "$DESIGN_SKILL_DIR/seed-canvas.mjs" --check "$OUT"
