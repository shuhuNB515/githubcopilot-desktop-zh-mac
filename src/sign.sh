#!/bin/bash
# 给「GitHub Copilot」副本重新签名（ad-hoc），使其允许注入动态库
set -eu
CN_HOME="${COPILOT_CN_DIR:-$HOME/Library/Application Support/CopilotCN}"
APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
ENT="$CN_HOME/ent.plist"

if [ ! -d "$APP" ]; then echo "找不到 $APP" >&2; exit 1; fi
if [ ! -f "$ENT" ]; then echo "找不到 $ENT" >&2; exit 1; fi

C="$APP/Contents"
echo "→ 签名内嵌组件"
codesign --force --sign - --timestamp=none "$C/Frameworks/"*.dylib
codesign --force --sign - --timestamp=none --options runtime --entitlements "$CN_HOME/ent-git-credential.plist" "$C/MacOS/git-credential-copilot" || true
codesign --force --sign - --timestamp=none --options runtime "$C/Resources/plugins/computer-use/computer-use-mcp" || true
codesign --force --sign - --deep --timestamp=none --options runtime "$C/Resources/plugins/computer-use/Copilot Computer Use.app" || true
echo "→ 签名主程序（约 1-2 分钟）"
codesign --force --sign - --timestamp=none --options runtime --entitlements "$ENT" "$APP"
echo "→ 完成"
