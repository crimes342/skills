#!/bin/bash
# hermes-cloak 一键安装脚本
# 适用于: Oracle Cloud ARM64 Ubuntu 无 GPU 服务器
# 用法: curl -fsSL https://your-domain.com/install.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo "============================================"
echo "  Hermes + CloakBrowser 安装脚本"
echo "  目标: ARM64 Ubuntu 无 GPU 服务器"
echo "============================================"
echo ""

# 检测架构
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    warn "当前架构为 $ARCH，非 ARM64。脚本仍可运行，但建议确认兼容性。"
fi

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log "检测到系统: $PRETTY_NAME ($ID $VERSION_ID)"
else
    error "无法检测操作系统"
fi

# ===== 1. 系统依赖 =====
log "安装系统依赖..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    python3 python3-pip python3-venv \
    libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    xvfb fonts-noto-color-emoji fonts-freefont-ttf fonts-unifont \
    2>/dev/null

log "系统依赖安装完成"

# ===== 2. 项目目录 =====
INSTALL_DIR="${HERMES_CLOAK_DIR:-$HOME/hermes-cloak}"
log "安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ===== 3. Python 虚拟环境 =====
log "创建 Python 虚拟环境..."
python3 -m venv .venv
source .venv/bin/activate

# ===== 4. 安装 CloakBrowser + MCP =====
log "安装 CloakBrowser..."
pip install --quiet cloakbrowser

log "预下载 ARM64 二进制..."
python -m cloakbrowser install 2>/dev/null || warn "二进制预下载跳过（首次使用时自动下载）"

log "安装 CloakBrowserMCP..."
pip install --quiet cloakbrowsermcp

# ===== 5. 验证安装 =====
log "验证安装..."
python -c "from cloakbrowser import launch; print('CloakBrowser: OK')" 2>/dev/null || error "CloakBrowser 安装失败"
cloakbrowsermcp --help >/dev/null 2>&1 || error "CloakBrowserMCP 安装失败"

# ===== 6. 配置目录 =====
log "创建配置目录..."
mkdir -p "$INSTALL_DIR/profiles"
mkdir -p "$INSTALL_DIR/scripts"

# 复制 Skills
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/../skills" ]; then
    cp -r "$SCRIPT_DIR/../skills" "$INSTALL_DIR/"
    log "Skills 已复制到 $INSTALL_DIR/skills/"
fi

# ===== 7. 生成 Hermes 配置 =====
log "生成 Hermes 配置模板..."
cat > "$INSTALL_DIR/hermes_config.yaml" << 'YAML'
# Hermes MCP 配置 — CloakBrowser
# 复制到 ~/.hermes/config.yaml 或在 Hermes 中导入

mcp_servers:
  cloakbrowser:
    command: cloakbrowsermcp
    args: ["--caps", "all"]
    timeout: 120
    env:
      CLOAK_HEADLESS: "true"           # ARM64 无 GPU 使用 headless
      CLOAK_HUMANIZE: "true"           # 人类行为模拟（必须开启）
      CLOAK_PROXY: ""                  # 可选：住宅代理地址
      CLOAK_PROFILE_DIR: "INSTALL_DIR/profiles"  # 持久化登录
YAML

sed -i "s|INSTALL_DIR|$INSTALL_DIR|g" "$INSTALL_DIR/hermes_config.yaml"

# ===== 8. Xvfb 启动脚本 =====
cat > "$INSTALL_DIR/scripts/start_xvfb.sh" << 'BASH'
#!/bin/bash
# 启动 Xvfb 虚拟显示（用于 headed 模式强反爬）
pkill Xvfb 2>/dev/null || true
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
export DISPLAY=:99
echo "Xvfb started on :99"
BASH
chmod +x "$INSTALL_DIR/scripts/start_xvfb.sh"

# ===== 9. 完成 =====
echo ""
echo "============================================"
echo -e "  ${GREEN}安装完成！${NC}"
echo "============================================"
echo ""
echo "安装目录: $INSTALL_DIR"
echo ""
echo "下一步:"
echo "  1. 将 hermes_config.yaml 复制到 Hermes 配置:"
echo "     cp $INSTALL_DIR/hermes_config.yaml ~/.hermes/config.yaml"
echo ""
echo "  2. 重启 Hermes:"
echo "     hermes restart"
echo ""
echo "  3. 验证 MCP 工具:"
echo "     hermes tools list | grep cloak"
echo ""
echo "  4. 测试登录:"
echo "     hermes chat"
echo '     > 用 CloakBrowser 登录 https://example.com, 用户名 admin, 密码 123'
echo ""
echo "  如需 headed 模式（强反爬站点）:"
echo "     bash $INSTALL_DIR/scripts/start_xvfb.sh"
echo "     修改 hermes_config.yaml: CLOAK_HEADLESS=false"
echo ""
