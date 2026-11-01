#!/bin/bash
# CopilotCN 卸载：删除启动器、已汉化的应用副本与运行时数据
set -u
CN_HOME="$HOME/Library/Application Support/CopilotCN"
DST_APP="${COPILOT_CN_APP:-$HOME/Applications/GitHub Copilot.app}"
LAUNCHER="$HOME/Applications/GitHub Copilot 中文版.app"

read -r -p "确认卸载 CopilotCN？将删除启动器、应用副本和运行时数据 [y/N] " ans
case "$ans" in
  y|Y) ;;
  *) echo "已取消"; exit 0 ;;
esac

[ -n "$LAUNCHER" ] && rm -rf "$LAUNCHER"
[ -n "$DST_APP" ] && rm -rf "$DST_APP"
[ -n "$CN_HOME" ] && rm -rf "$CN_HOME"
echo "已卸载。/Applications 中的官方应用未受影响。"
