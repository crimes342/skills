#!/bin/bash
# hermes-notebooklm 一键安装脚本
# 在已有 CloakBrowser 环境上追加 NotebookLM 适配

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo "============================================"
echo "  Hermes + NotebookLM 适配安装"
echo "  基于 win4r/notebooklm-py@v0.3.4-hermes.4"
echo "============================================"
echo ""

# ===== 0. 前置检查 =====
log "检查前置条件..."

# 检查 Hermes
command -v hermes >/dev/null 2>&1 || error "Hermes 未安装，请先安装 Hermes Agent"

# 检查 CloakBrowser skill
if [ ! -d "$HOME/.hermes/skills/cloakbrowser" ]; then
    warn "CloakBrowser skill 未找到，建议先安装 crimes342/skills 的 cloakbrowser 技能"
fi

# 检查 Python
command -v python3 >/dev/null 2>&1 || error "Python3 未安装"

# ===== 1. 安装 notebooklm-py =====
log "安装 notebooklm-py (win4r fork v0.3.4-hermes.4)..."
pip install "notebooklm-py[browser,cookies] @ git+https://github.com/win4r/notebooklm-py@v0.3.4-hermes.4" 2>/dev/null || {
    warn "pip 安装失败，尝试使用 venv..."
    VENV_DIR="$HOME/.hermes/hermes-agent/venv"
    if [ -d "$VENV_DIR" ]; then
        "$VENV_DIR/bin/pip" install "notebooklm-py[browser,cookies] @ git+https://github.com/win4r/notebooklm-py@v0.3.4-hermes.4"
    else
        error "无法安装 notebooklm-py"
    fi
}

# ===== 2. Playwright Chromium =====
log "安装 Playwright Chromium..."
playwright install chromium 2>/dev/null || warn "Playwright 安装跳过（bridge 模式不需要）"

# ===== 3. 安装 Hermes Skill =====
log "安装 Hermes NotebookLM Skill..."
hermes skills tap add win4r/notebooklm-py 2>/dev/null || true
hermes skills install win4r/notebooklm-py/skills/notebooklm --force 2>/dev/null || warn "Skill 安装需手动完成"

# ===== 4. CLI PATH =====
log "配置 CLI PATH..."
mkdir -p ~/.local/bin
if [ -f "$HOME/.hermes/hermes-agent/venv/bin/notebooklm" ]; then
    ln -sf "$HOME/.hermes/hermes-agent/venv/bin/notebooklm" ~/.local/bin/notebooklm
fi

# ===== 5. 部署 Bridge 脚本 =====
log "部署 Cookie 桥接脚本..."
BRIDGE_DIR="$HOME/hermes-browser"
mkdir -p "$BRIDGE_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/cloak2nlm_bridge.py" "$BRIDGE_DIR/"

# 安装 bridge 依赖
pip install httpx websockets 2>/dev/null || \
    "$HOME/.hermes/hermes-agent/venv/bin/pip" install httpx websockets 2>/dev/null || \
    warn "bridge 依赖需手动安装: pip install httpx websockets"

# ===== 6. 配置环境变量 =====
log "配置环境变量..."
HERMES_ENV="$HOME/.hermes/.env"
mkdir -p "$HOME/.hermes"

if ! grep -q "NOTEBOOKLM_REFRESH_CMD" "$HERMES_ENV" 2>/dev/null; then
    cat >> "$HERMES_ENV" << 'EOF'

# NotebookLM Cookie 自动刷新
NOTEBOOKLM_REFRESH_CMD="python3 ~/hermes-browser/cloak2nlm_bridge.py"
NOTEBOOKLM_HOME="~/.notebooklm"
NOTEBOOKLM_PROFILE="default"
EOF
    log "环境变量已写入: $HERMES_ENV"
else
    warn "NOTEBOOKLM_REFRESH_CMD 已存在，跳过"
fi

# ===== 7. 创建存储目录 =====
mkdir -p "$HOME/.notebooklm/profiles/default"

# ===== 8. 配置 Cron（15分钟刷新）=====
log "配置 15 分钟 Cookie 刷新 Cron..."
CRON_CMD="*/15 * * * * python3 $BRIDGE_DIR/cloak2nlm_bridge.py >> /tmp/nlm-cookie-refresh.log 2>&1"
(crontab -l 2>/dev/null | grep -v "cloak2nlm_bridge"; echo "$CRON_CMD") | crontab -
log "Cron 已配置: 每15分钟刷新 Cookie"

# ===== 9. 完成 =====
echo ""
echo "============================================"
echo -e "  ${GREEN}安装完成！${NC}"
echo "============================================"
echo ""
echo "下一步:"
echo "  1. 通过 CloakBrowser 登录 Google:"
echo '     Hermes > "帮我登录 Google，我要用 NotebookLM"'
echo ""
echo "  2. 验证认证:"
echo "     notebooklm auth check --test"
echo ""
echo "  3. 使用 NotebookLM:"
echo '     Hermes > "用 NotebookLM 创建一个笔记本，主题是 AI"'
echo ""
echo "  Cookie 将每15分钟自动刷新"
echo "  日志: tail -f /tmp/nlm-cookie-refresh.log"
echo ""
