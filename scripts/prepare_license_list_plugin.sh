#!/bin/bash
# 内容を確認した LicenseList 2.5.0 のプラグインだけを承認する。
# 既存の承認は保持し、再実行しても同じエントリーを増やさない。
set -euo pipefail
security_dir="$HOME/Library/org.swift.swiftpm/security"
mkdir -p "$security_dir"
approval_file="$(dirname "$0")/license_list_plugin.json"
if [ -f "$security_dir/plugins.json" ]; then
  jq -s 'add | unique' "$security_dir/plugins.json" "$approval_file" > "$security_dir/plugins.json.tmp"
else
  cp "$approval_file" "$security_dir/plugins.json.tmp"
fi
mv "$security_dir/plugins.json.tmp" "$security_dir/plugins.json"
