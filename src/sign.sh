#!/bin/bash
# 给「GitHub Copilot」副本重新签名（ad-hoc），使其允许注入动态库
set -eu
CN_HOME="${COPILOT_CN_DIR:-$HOME/Library/Application Support/CopilotCN}"
APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
ENT="$CN_HOME/ent.plist"

if [ ! -d "$APP" ]; then echo "找不到 $APP" >&2; exit 1; fi
if [ ! -f "$ENT" ]; then echo "找不到 $ENT" >&2; exit 1; fi

# 先结束仍占用文件的实例/子进程，否则 codesign 会报 Write permissions error
pkill -f 'GitHub Copilot.app/Contents/MacOS/github' 2>/dev/null || true
pkill -f 'copilot-runtime' 2>/dev/null || true
for i in $(seq 1 24); do
  pgrep -f 'GitHub Copilot.app/Contents/MacOS/github' >/dev/null 2>&1 || break
  sleep 0.25
done
sleep 0.4

C="$APP/Contents"
sign_all() {
  codesign --force --sign - --timestamp=none "$C/Frameworks/"*.dylib
  codesign --force --sign - --timestamp=none --options runtime --entitlements "$CN_HOME/ent-git-credential.plist" "$C/MacOS/git-credential-copilot" || true
  codesign --force --sign - --timestamp=none --options runtime "$C/Resources/plugins/computer-use/computer-use-mcp" || true
  codesign --force --sign - --deep --timestamp=none --options runtime "$C/Resources/plugins/computer-use/Copilot Computer Use.app" || true
  codesign --force --sign - --timestamp=none --options runtime --entitlements "$ENT" "$APP"
}

echo "→ 签名内嵌组件"
if ! sign_all; then
  echo "→ 首次签名失败，等待后重试一次"
  sleep 2
  sign_all
fi

if ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q disable-library-validation; then
  echo "签名后仍未带上注入权限" >&2
  exit 1
fi
echo "→ 完成"
