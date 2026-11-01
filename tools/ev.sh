#!/bin/bash
# 用法: ev.sh <js文件> —— 通过原生 evaluateJavaScript 通道执行任意 JS
set -u
CN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RT="${COPILOT_CN_DIR:-$CN_ROOT/runtime}"
F="$RT/queue/eval-$(date +%s%N).js"
cat "$1" > "$F"
R="$F.result.json"
for i in $(seq 1 80); do
  if [ -f "$R" ]; then cat "$R"; echo; rm -f "$R"; exit 0; fi
  sleep 0.2
done
echo '{"ok":false,"value":"timeout"}'
