# Cookie 静默刷新技能

## 概述
每15分钟自动从 CloakBrowser 提取 Google Cookie 并同步到 notebooklm-py，确保 NotebookLM API 始终可用。

## 刷新机制

### 三层保障

```
层1 — 定时刷新（cron）
  每15分钟执行 bridge 脚本
  无论 Cookie 是否过期都刷新
  → 确保 Cookie 始终新鲜

层2 — 按需刷新（NOTEBOOKLM_REFRESH_CMD）
  notebooklm-py 遇到 401 时自动触发
  一次进程生命周期只触发一次
  → 兜底保障

层3 — 持久化 Profile
  CloakBrowser profile_dir 保存 Google 登录态
  即使 bridge 失败，CloakBrowser 仍保持登录
  → 最后防线
```

### 数据流

```
CloakBrowser (CDP 127.0.0.1:9222)
    │
    │ Network.getCookies (WebSocket)
    ▼
cloak2nlm_bridge.py
    │
    │ CDP → Playwright storage_state.json
    ▼
~/.notebooklm/profiles/default/storage_state.json
    │
    │ notebooklm-py 自动读取
    ▼
Google NotebookLM API
```

## Cron 配置

```bash
# 每15分钟执行
*/15 * * * * python3 ~/hermes-browser/cloak2nlm_bridge.py >> /tmp/nlm-cookie-refresh.log 2>&1
```

## 环境变量

```bash
# ~/.hermes/.env
NOTEBOOKLM_REFRESH_CMD="python3 ~/hermes-browser/cloak2nlm_bridge.py"
```

## Hermes 提示词

当用户要求"刷新 Cookie"、"更新认证"、"Cookie 过期了"时：
1. 检查 CloakBrowser 是否运行：`curl -s http://127.0.0.1:9222/json/version`
2. 如果未运行，通过 google-auth skill 启动并登录
3. 执行 bridge 脚本：`python3 ~/hermes-browser/cloak2nlm_bridge.py`
4. 验证：`notebooklm auth check --test`
5. 如果 bridge 失败（Google 会话过期），重新执行 google-auth 完整流程

## 监控

```bash
# 查看刷新日志
tail -f /tmp/nlm-cookie-refresh.log

# 检查 Cookie 文件新鲜度
ls -la ~/.notebooklm/profiles/default/storage_state.json

# 手动触发刷新
python3 ~/hermes-browser/cloak2nlm_bridge.py
```
