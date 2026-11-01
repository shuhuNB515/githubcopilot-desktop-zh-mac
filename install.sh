#!/bin/bash
# CopilotCN 安装脚本：复制应用副本、重签名、安装注入库与启动器
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CN_HOME="$HOME/Library/Application Support/CopilotCN"
SRC_APP="${COPILOT_CN_SRC:-/Applications/GitHub Copilot.app}"
DST_APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
LAUNCHER="$HOME/Applications/GitHub Copilot 中文版.app"

echo "== CopilotCN 安装 =="
if [ ! -d "$SRC_APP" ]; then
  echo "找不到源应用：$SRC_APP" >&2
  exit 1
fi
mkdir -p "$CN_HOME" "$(dirname "$DST_APP")"

echo "→ 安装运行时文件到 $CN_HOME"
cp "$HERE/runtime/translator.js" "$HERE/runtime/bridge.js" "$HERE/runtime/collector.js" \
   "$HERE/runtime/dict.json" "$HERE/runtime/menu.json" "$CN_HOME/"
cp "$HERE/src/launch.sh" "$HERE/src/sign.sh" "$CN_HOME/"
chmod +x "$CN_HOME/launch.sh" "$CN_HOME/sign.sh"
cp "$HERE/src/ent.plist" "$CN_HOME/ent.plist"
cp "$HERE/src/ent-git-credential.plist" "$CN_HOME/ent-git-credential.plist"

echo "→ 安装注入库"
if pgrep -f "Applications/GitHub Copilot.app/Contents/MacOS/github" >/dev/null 2>&1; then
  echo "  注意：检测到中文版正在运行，请先退出再重启以生效"
fi
# 用「临时文件 + 原子替换」避免覆盖正在被映射的 dylib 导致进程崩溃
if [ -f "$HERE/dist/CopilotCN.dylib" ]; then
  cp "$HERE/dist/CopilotCN.dylib" "$CN_HOME/.CopilotCN.dylib.new"
elif [ -f "$HERE/out/CopilotCN.dylib" ]; then
  cp "$HERE/out/CopilotCN.dylib" "$CN_HOME/.CopilotCN.dylib.new"
else
  clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=11.0 \
        -framework Foundation -framework AppKit -framework WebKit \
        -o "$CN_HOME/.CopilotCN.dylib.new" "$HERE/src/inject.m"
fi
codesign --force --sign - "$CN_HOME/.CopilotCN.dylib.new" >/dev/null 2>&1 || true
mv -f "$CN_HOME/.CopilotCN.dylib.new" "$CN_HOME/CopilotCN.dylib"

SRC_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$SRC_APP/Contents/Info.plist" 2>/dev/null || echo 0)
DST_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$DST_APP/Contents/Info.plist" 2>/dev/null || echo none)
if [ ! -d "$DST_APP" ] || [ "$SRC_VER" != "$DST_VER" ]; then
  echo "→ 复制应用副本到 $DST_APP（版本 $SRC_VER）"
  rm -rf "$DST_APP"
  cp -cR "$SRC_APP" "$(dirname "$DST_APP")/" 2>/dev/null || cp -R "$SRC_APP" "$(dirname "$DST_APP")/"
fi

if ! codesign -d --entitlements :- "$DST_APP" 2>/dev/null | grep -q disable-library-validation; then
  echo "→ 重新签名（ad-hoc，约 1-2 分钟）"
  COPILOT_CN_APP="$DST_APP" COPILOT_CN_DIR="$CN_HOME" "$CN_HOME/sign.sh"
else
  echo "→ 应用已签名，跳过"
fi

echo "→ 生成启动器 $LAUNCHER"
rm -rf "$LAUNCHER"
mkdir -p "$LAUNCHER/Contents/MacOS" "$LAUNCHER/Contents/Resources"
cp "$SRC_APP/Contents/Resources/icon.icns" "$LAUNCHER/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cat > "$LAUNCHER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GitHub Copilot 中文版</string>
  <key>CFBundleDisplayName</key><string>GitHub Copilot 中文版</string>
  <key>CFBundleIdentifier</key><string>com.copilotcn.launcher</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
clang -O2 -o "$LAUNCHER/Contents/MacOS/launcher" "$HERE/src/launcher.c"
codesign --force --sign - "$LAUNCHER" >/dev/null 2>&1 || true

echo
echo "安装完成！"
echo "  启动：双击「${LAUNCHER}」"
echo "  已汉化的应用副本：$DST_APP"
echo "  词典与日志：$CN_HOME"
echo "  注意：原 /Applications 里的应用仍为英文版，请用上面的启动器打开中文版。"
