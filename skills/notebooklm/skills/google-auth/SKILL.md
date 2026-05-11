# Google 认证技能

## 概述
使用 CloakBrowser 登录 Google 并提取会话 Cookie，供 NotebookLM 使用。

## 依赖
- cloakbrowser skill（提供 cloak_* 工具）
- cloakbrowsermcp MCP Server

## 执行流程

### Step 1: 启动 CloakBrowser
```
cloak_launch(headless=true, humanize=true, profile_dir="/data/cloak_profiles/google")
```

### Step 2: 导航到 Google 登录
```
cloak_navigate(pid, "https://accounts.google.com/ServiceLogin?continue=https://notebooklm.google.com")
```

### Step 3: 获取页面快照
```
cloak_snapshot(pid)
→ 识别: [@e1]=邮箱输入框, [@e2]=下一步按钮
```

### Step 4: 输入邮箱
```
cloak_click(pid, "@e1")
cloak_type(pid, "@e1", "your-email@gmail.com", delay=80)
cloak_sleep(1)
cloak_click(pid, "@e2")  # 点击"下一步"
cloak_sleep(2)
```

### Step 5: 输入密码
```
cloak_snapshot(pid)  → 识别密码框
cloak_type(pid, "@e3", "your-password", delay=60)
cloak_sleep(0.5)
cloak_click(pid, "@e4")  # 点击"下一步"
cloak_sleep(3)
```

### Step 6: 处理 2FA（如需要）
```
cloak_snapshot(pid)  → 检查是否需要验证码
# 如需要：cloak_type(pid, "@e5", "123456")
```

### Step 7: 验证登录成功
```
cloak_snapshot(pid)  → 检查是否到达 myaccount.google.com 或 notebooklm.google.com
```

### Step 8: 提取 Cookie 并桥接
```
# 执行 bridge 脚本
python3 ~/hermes-browser/cloak2nlm_bridge.py
```

### Step 9: 验证
```
notebooklm auth check --test  → 应全部 ✓
notebooklm list               → 应能列出笔记本
```

## Hermes 提示词

当用户要求"登录 Google"、"认证 NotebookLM"、"刷新 Cookie"时：
1. 检查当前认证状态：`notebooklm auth check --test`
2. 如果已认证，跳过登录
3. 如果未认证，按上述流程执行 CloakBrowser 登录
4. 登录后执行 bridge 脚本同步 Cookie
5. 验证并报告结果

## 注意事项

- CloakBrowser 必须保持运行状态（profile 持久化）
- Google 可能要求验证新设备，Hermes 会通过 snapshot 检测并处理
- 频繁重新登录可能触发 48 小时冷却期，避免重启 CloakBrowser
