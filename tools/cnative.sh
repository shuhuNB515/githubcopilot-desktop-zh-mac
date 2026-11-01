#!/bin/bash
# 用法: cnative.sh '{"op":"menudump"}' —— 触发注入器里的原生操作（菜单导出/菜单点击）
set -u
CN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RT="${COPILOT_CN_DIR:-$CN_ROOT/runtime}"
F="$RT/queue/native-$(date +%s%N)-$RANDOM.json"
printf '%s' "$1" > "$F"
R="${F%.json}.result.json"
for i in $(seq 1 60); do
  if [ -f "$R" ]; then cat "$R"; echo; rm -f "$R"; exit 0; fi
  sleep 0.2
done
echo '{"ok":false,"value":"timeout"}'
