#!/bin/bash
# 启动 Xvfb 虚拟显示（用于 headed 模式强反爬站点）

set -euo pipefail

DISPLAY_NUM="${1:-99}"
RESOLUTION="${2:-1920x1080x24}"

# 停止已有实例
pkill Xvfb 2>/dev/null || true
sleep 0.5

# 启动虚拟帧缓冲
Xvfb :${DISPLAY_NUM} \
    -screen 0 ${RESOLUTION} \
    -ac \
    +extension GLX \
    +render \
    -noreset &

export DISPLAY=:${DISPLAY_NUM}

echo "============================================"
echo "  Xvfb 虚拟显示已启动"
echo "  DISPLAY=:${DISPLAY_NUM}"
echo "  分辨率: ${RESOLUTION}"
echo "============================================"
echo ""
echo "在当前 shell 中运行 CloakBrowser:"
echo "  export DISPLAY=:${DISPLAY_NUM}"
echo "  python3 -c \"from cloakbrowser import launch; b = launch(headless=False); print('OK'); b.close()\""
