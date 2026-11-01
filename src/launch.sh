#!/bin/bash
# 启动「GitHub Copilot 中文版」：确保应用已打补丁，然后带注入库启动
set -u
CN_HOME="$HOME/Library/Application Support/CopilotCN"
APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
DYLIB="$CN_HOME/CopilotCN.dylib"

if [ ! -x "$APP/Contents/MacOS/github" ]; then
  osascript -e 'display alert "找不到已汉化的 GitHub Copilot" message "请先运行 install.sh"' >/dev/null 2>&1
  echo "找不到 $APP，请先运行 install.sh" >&2
  exit 1
fi
if [ ! -f "$DYLIB" ]; then
  echo "找不到注入库 $DYLIB，请先运行 install.sh" >&2
  exit 1
fi

# 应用被自动更新后会恢复官方签名，此时需要重新签名才能注入
if ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q disable-library-validation; then
  echo "检测到应用签名已失效（可能刚更新过），正在重新签名……" >&2
  "$CN_HOME/sign.sh" || exit 1
fi

mkdir -p "$CN_HOME/dumps" "$CN_HOME/queue"
rm -f "$CN_HOME/queue/"*.json "$CN_HOME/queue/"*.js "$CN_HOME/queue/"*.busy 2>/dev/null

exec env COPILOT_CN_DIR="$CN_HOME" DYLD_INSERT_LIBRARIES="$DYLIB" "$APP/Contents/MacOS/github"
