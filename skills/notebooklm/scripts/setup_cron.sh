#!/bin/bash
# 配置 15 分钟 Cookie 刷新 Cron

set -euo pipefail

BRIDGE_DIR="${HOME}/hermes-browser"
CRON_CMD="*/15 * * * * python3 ${BRIDGE_DIR}/cloak2nlm_bridge.py >> /tmp/nlm-cookie-refresh.log 2>&1"

echo "配置 Cron: 每15分钟刷新 NotebookLM Cookie"

# 移除旧的 bridge cron（如有）
(crontab -l 2>/dev/null | grep -v "cloak2nlm_bridge"; echo "$CRON_CMD") | crontab -

echo "当前 Cron 配置:"
crontab -l | grep cloak2nlm

echo ""
echo "查看日志: tail -f /tmp/nlm-cookie-refresh.log"
echo "手动刷新: python3 ${BRIDGE_DIR}/cloak2nlm_bridge.py"
