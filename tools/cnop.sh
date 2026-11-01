#!/bin/bash
# 用法: cnop.sh '{"op":"click","args":{"text":"Settings"}}' —— 发送一条指令给 App 页面执行
set -u
CN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RT="${COPILOT_CN_DIR:-$CN_ROOT/runtime}"
F="$RT/queue/cmd-$(date +%s%N)-$RANDOM.json"
printf '%s' "$1" > "$F"
R="$F.result.json"
for i in $(seq 1 80); do
  if [ -f "$R" ]; then cat "$R"; echo; rm -f "$R"; exit 0; fi
  sleep 0.25
done
echo '{"ok":false,"error":"timeout waiting for result"}'
