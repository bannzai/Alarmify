#!/usr/bin/env bash
# design_handoff/canvas/*.dc.html を 390x844 (2x) で撮影して design_handoff/png/ に保存する (冪等: 同名 PNG を上書き)。
# agent-browser のセッション名は worktree 名 (~/.claude/documents/rules/agent-browser-session-naming.md)
set -u
CANVAS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CANVAS/../.." && pwd)"
PNG="$ROOT/design_handoff/png"
export AGENT_BROWSER_SESSION="$(basename "$ROOT")"
mkdir -p "$PNG" "$ROOT/tmp"
LOG="$ROOT/tmp/shoot-artboards.log"
: > "$LOG"
agent-browser --session "$AGENT_BROWSER_SESSION" set viewport 390 844 2 >> "$LOG" 2>&1
while read -r f; do
  name="${f%.dc.html}"
  agent-browser --session "$AGENT_BROWSER_SESSION" open "file://$CANVAS/$f" >> "$LOG" 2>&1
  agent-browser --session "$AGENT_BROWSER_SESSION" wait 300 >> "$LOG" 2>&1
  agent-browser --session "$AGENT_BROWSER_SESSION" screenshot "$PNG/$name.png" >> "$LOG" 2>&1
  echo "$name exit=$?" >> "$LOG"
done < "$CANVAS/files.txt"
agent-browser --session "$AGENT_BROWSER_SESSION" close >> "$LOG" 2>&1
echo "done" >> "$LOG"
grep -c 'exit=0' "$LOG"
