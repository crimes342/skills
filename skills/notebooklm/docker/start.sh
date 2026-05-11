#!/bin/bash
set -e

# 启动 Xvfb
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
export DISPLAY=:99
sleep 1

# 启动 cron
cron

# 执行首次 bridge（如已有 Cookie）
python3 /app/cloak2nlm_bridge.py 2>/dev/null || true

echo "Hermes NotebookLM 容器已启动"
echo "Cookie 将每15分钟自动刷新"

# 保持容器运行
tail -f /var/log/nlm-bridge.log 2>/dev/null || tail -f /dev/null
