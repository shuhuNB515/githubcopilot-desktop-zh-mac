#!/bin/bash
# 构建 CopilotCN：编译注入库，并（可选）从 TSV 重建词典
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

mkdir -p dist
echo "→ 编译 CopilotCN.dylib"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=11.0 \
  -framework Foundation -framework AppKit -framework WebKit \
  -o dist/CopilotCN.dylib src/inject.m
codesign --force --sign - dist/CopilotCN.dylib >/dev/null 2>&1 || true

if [ "${1:-}" = "--dict" ] && command -v python3 >/dev/null; then
  echo "→ 重建 dict.json"
  python3 tools/build_dict.py
fi
echo "完成：dist/CopilotCN.dylib"
