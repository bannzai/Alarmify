#!/usr/bin/env bash
# design_handoff/canvas/*.dc.html を 390x844 (2x) で撮影して design_handoff/png/ に保存する (冪等: 同名 PNG を上書き)。
# agent-browser のセッション名は worktree 名 (~/.claude/documents/rules/agent-browser-session-naming.md)。
# open に失敗したアートボードは撮影せず (前の画面で上書きしない)、1 つでも失敗があれば exit 1 で終わる
set -u
CANVAS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CANVAS/../.." && pwd)"
PNG="$ROOT/design_handoff/png"
export AGENT_BROWSER_SESSION="$(basename "$ROOT")"
mkdir -p "$PNG" "$ROOT/tmp"
LOG="$ROOT/tmp/shoot-artboards.log"
: > "$LOG"
failed=0
if ! agent-browser --session "$AGENT_BROWSER_SESSION" set viewport 390 844 2 >> "$LOG" 2>&1; then
  echo "viewport failed" >> "$LOG"
  failed=1
fi
while read -r f; do
  name="${f%.dc.html}"
  if ! agent-browser --session "$AGENT_BROWSER_SESSION" open "file://$CANVAS/$f" >> "$LOG" 2>&1; then
    echo "$name open failed" >> "$LOG"
    failed=1
    continue
  fi
  agent-browser --session "$AGENT_BROWSER_SESSION" wait 300 >> "$LOG" 2>&1
  if agent-browser --session "$AGENT_BROWSER_SESSION" screenshot "$PNG/$name.png" >> "$LOG" 2>&1; then
    echo "$name exit=0" >> "$LOG"
  else
    echo "$name screenshot failed" >> "$LOG"
    failed=1
  fi
done < "$CANVAS/files.txt"
agent-browser --session "$AGENT_BROWSER_SESSION" close >> "$LOG" 2>&1
echo "ok=$(grep -c 'exit=0' "$LOG") failed=$failed"
exit "$failed"
