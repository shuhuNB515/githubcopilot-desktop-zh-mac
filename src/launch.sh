#!/bin/bash
# 启动「GitHub Copilot 中文版」：确保应用已打补丁，然后带注入库启动
set -u
CN_HOME="$HOME/Library/Application Support/CopilotCN"
APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
DYLIB="$CN_HOME/CopilotCN.dylib"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"GitHub Copilot 中文版\"" >/dev/null 2>&1 || true
}
alert() {
  /usr/bin/osascript -e "display alert \"GitHub Copilot 中文版\" message \"$1\"" >/dev/null 2>&1 || true
}

if [ ! -x "$APP/Contents/MacOS/github" ]; then
  alert "找不到已汉化的应用副本，请重新运行 install.sh"
  exit 1
fi
if [ ! -f "$DYLIB" ]; then
  alert "找不到注入库，请重新运行 install.sh"
  exit 1
fi

# 应用自动更新后会恢复官方签名，此时必须重新签名才能注入
if ! codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q disable-library-validation; then
  notify "应用刚更新过，正在重新签名，请稍候 1-2 分钟…"
  echo "检测到应用签名已还原（通常刚自动更新过），正在重新签名……" >&2
  if ! "$CN_HOME/sign.sh" >>"$CN_HOME/sign.log" 2>&1; then
    alert "重新签名失败，请打开终端运行：~/Library/Application Support/CopilotCN/sign.sh"
    exit 1
  fi
  notify "签名完成，正在启动"
fi

mkdir -p "$CN_HOME/dumps" "$CN_HOME/queue"
rm -f "$CN_HOME/queue/"*.json "$CN_HOME/queue/"*.js "$CN_HOME/queue/"*.busy 2>/dev/null

exec env COPILOT_CN_DIR="$CN_HOME" DYLD_INSERT_LIBRARIES="$DYLIB" "$APP/Contents/MacOS/github"
