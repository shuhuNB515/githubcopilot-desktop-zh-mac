#!/bin/bash
# 热更新词典与翻译器（无需重启 App）
set -u
CN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RT="${COPILOT_CN_DIR:-$CN_ROOT/runtime}"
python3 "$CN_ROOT/tools/build_dict.py" >/dev/null
TMP=/tmp/cn-reload-$$.js
{ printf 'window.__cnTranslatorInstalled=false;window.__CN_DICT='; cat "$RT/dict.json"; printf ';\n'; cat "$RT/translator.js"; } > "$TMP"
"$CN_ROOT/tools/ev.sh" "$TMP"
rm -f "$TMP"
