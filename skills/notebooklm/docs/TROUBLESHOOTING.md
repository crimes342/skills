# 故障排查手册 — Hermes NotebookLM

## 常见问题

### 1. bridge 报 "无法连接 CloakBrowser CDP"
**原因**：CloakBrowser 未启动
**解决**：
```bash
# 通过 Hermes 启动 CloakBrowser
hermes > "启动 CloakBrowser"
# 或手动检查
curl -s http://127.0.0.1:9222/json/version
```

### 2. bridge 成功但 notebooklm auth check 失败
**原因**：Cookie 中缺少关键字段（可能登录未完成就跑了 bridge）
**解决**：
```bash
# 重新走 Google 登录流程
hermes > "帮我重新登录 Google"
# 确保登录完成后再执行 bridge
python3 ~/hermes-browser/cloak2nlm_bridge.py
notebooklm auth check --test
```

### 3. Cookie 自动刷新失效
**原因**：NOTEBOOKLM_REFRESH_CMD 未加载或 cron 未配置
**解决**：
```bash
# 检查环境变量
echo $NOTEBOOKLM_REFRESH_CMD

# 检查 cron
crontab -l | grep cloak2nlm

# 手动刷新
python3 ~/hermes-browser/cloak2nlm_bridge.py
```

### 4. 生成音频/视频超时
**原因**：Google 服务端限流
**解决**：
```bash
# 使用 --wait 参数等待完成
notebooklm generate audio "..." --wait
# 内部 timeout 5分钟，通常够用
```

### 5. Google 要求 2FA
**原因**：新设备登录触发验证
**解决**：
Hermes 通过 cloak_snapshot 检测页面，按提示用 cloak_type 输入验证码。
支持 TOTP：向 Hermes 提供密钥即可。

### 6. rookiepy --browser-cookies 不工作
**原因**：ARM64 无头服务器无本地浏览器
**解决**：这是预期行为。正确方式是用 bridge.py 从 CDP 导出 Cookie。

### 7. 48 小时登录冷却
**原因**：频繁重新登录触发 Google 风控
**解决**：
- 保持 CloakBrowser 运行不要频繁重启
- 使用 profile 持久化登录态
- Cron 15分钟刷新避免 Cookie 过期

### 8. notebooklm CLI 找不到
**原因**：PATH 未配置
**解决**：
```bash
ln -sf ~/.hermes/hermes-agent/venv/bin/notebooklm ~/.local/bin/notebooklm
export PATH="$HOME/.local/bin:$PATH"
```

### 9. Skill 未被 Hermes 识别
**原因**：Skill 安装失败或 Hermes 未重启
**解决**：
```bash
hermes skills list  # 检查是否包含 notebooklm
hermes skills tap add win4r/notebooklm-py
hermes skills install win4r/notebooklm-py/skills/notebooklm --force
hermes restart
```

### 10. storage_state.json 权限问题
**原因**：文件权限不正确
**解决**：
```bash
chmod 600 ~/.notebooklm/profiles/default/storage_state.json
```
