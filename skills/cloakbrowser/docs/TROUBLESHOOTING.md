# 故障排查手册

## 常见问题

### 1. Segmentation fault
**原因**：缺少系统依赖库
**解决**：
```bash
sudo apt install -y \
  libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
  libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
  libgbm1 libpango-1.0-0 libcairo2 libasound2t64
```

### 2. 浏览器启动超时
**原因**：`/dev/shm` 空间不足
**解决**：
```bash
sudo mount -o remount,size=2G /dev/shm
# 或在 launch 时添加: args=["--disable-dev-shm-usage"]
```

### 3. 登录后 Cookie 丢失
**原因**：未使用持久化 profile
**解决**：launch 时指定 `profile_dir` 参数

### 4. 被目标网站检测
**原因**：代理 IP 质量差或指纹重复
**解决**：
- 更换住宅代理
- 使用不同的 `fingerprint_seed`
- 启用 `humanize=True`
- 切换到 headed + Xvfb 模式

### 5. reCAPTCHA 评分低
**原因**：使用了 fill 而非 type，或行为过于机械
**解决**：
- 用 `cloak_type` 替代 `cloak_fill`
- 增加 delay（80-120ms/字符）
- 用 `cloak_sleep()` 替代 `wait_for_timeout()`
- 启用 `humanize=True`

### 6. ARM64 二进制下载失败
**原因**：网络问题或平台不支持
**解决**：
```bash
# 手动下载
python -m cloakbrowser install --platform linux-arm64
# 或使用 Docker 镜像（已内置）
```

### 7. Xvfb 相关问题
**症状**：headed 模式启动失败
**解决**：
```bash
# 检查 Xvfb 是否运行
ps aux | grep Xvfb

# 手动启动
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99

# 验证
xdpyinfo -display :99
```

### 8. MCP 连接失败
**症状**：Hermes 无法调用 cloak_* 工具
**解决**：
```bash
# 测试 MCP Server 是否正常
cloakbrowsermcp --caps all  # 应无报错启动

# 检查 Hermes 配置
cat ~/.hermes/config.yaml | grep -A5 cloakbrowser

# 重启 Hermes
hermes restart
hermes tools list | grep cloak
```

### 9. 内存不足
**症状**：进程被 OOM Killer 终止
**解决**：
```bash
# 限制浏览器内存
launch(args=["--disable-dev-shm-usage", "--max-old-space-size=512"])

# 使用 cgroup 限制
sudo systemd-run --scope -p MemoryMax=2G --user hermes
```

### 10. 字体显示异常
**症状**：页面文字渲染为方块
**解决**：
```bash
sudo apt install -y fonts-noto-color-emoji fonts-freefont-ttf fonts-unifont
# Docker 镜像已内置字体
```
