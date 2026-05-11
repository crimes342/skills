#!/bin/bash
# 生成 Hermes 配置并应用

set -euo pipefail

INSTALL_DIR="${HERMES_CLOAK_DIR:-$HOME/hermes-cloak}"
HERMES_DIR="${HOME}/.hermes"

# 确保 Hermes 配置目录存在
mkdir -p "$HERMES_DIR"

# 检查是否已有配置
if [ -f "$HERMES_DIR/config.yaml" ]; then
    echo "检测到已有 Hermes 配置: $HERMES_DIR/config.yaml"
    read -p "是否备份并覆盖？(y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$HERMES_DIR/config.yaml" "$HERMES_DIR/config.yaml.bak.$(date +%s)"
        echo "已备份原配置"
    else
        echo "跳过配置写入，请手动合并以下内容到 $HERMES_DIR/config.yaml:"
        echo ""
        cat "$INSTALL_DIR/hermes_config.yaml"
        exit 0
    fi
fi

# 写入配置
cp "$INSTALL_DIR/hermes_config.yaml" "$HERMES_DIR/config.yaml"
echo "配置已写入: $HERMES_DIR/config.yaml"

# 提示重启
echo ""
echo "请重启 Hermes 使配置生效:"
echo "  hermes restart"
echo "  hermes tools list | grep cloak"
