#!/bin/bash
set -e

# 启动 Xvfb 虚拟显示
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
export DISPLAY=:99

# 等待 Xvfb 就绪
sleep 1

echo "Xvfb started on :99"
echo "Starting CloakBrowser MCP Server..."

# 启动 MCP Server (stdio 模式)
exec cloakbrowsermcp --caps all
