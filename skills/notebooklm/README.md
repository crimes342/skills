# Hermes + NotebookLM 适配方案

> 在 `crimes342/skills` 的 CloakBrowser 架构下，为 Hermes Agent 适配 Google NotebookLM 全功能自动化。

---

## 一、四方案交叉验证结论

| 维度 | D方案3 | G方案4 | M方案2 | Z方案1 | **综合最优** |
|------|--------|--------|--------|--------|-------------|
| 仓库选型 | win4r fork ✅ | 融合两家 | win4r fork ✅ | win4r fork ✅ | **D/M/Z** — win4r 有 Hermes 适配 |
| 架构模式 | 双 MCP 通道 | 双核驱动(浏览器+API) | CLI Skill（不自建MCP） | 独立 Skill + 共享认证 | **M/Z** — 最轻量 |
| 认证方式 | --browser-cookies + auto-refresh | CloakBrowser 登录 + Cookie 桥接 | CDP bridge + REFRESH_CMD | cloak_get_cookies → storage_state | **M** — CDP bridge 最可靠 |
| Cookie 刷新 | NOTEBOOKLM_REFRESH_CMD | 自研桥接脚本 | 80行 bridge.py | 环境变量注入 | **M** — 最简洁 |
| 自研代码量 | 配置为主 | ~100行 MCP Server | ~80行 bridge.py | 配置为主 | **M** — 最小代码量 |
| 维护风险 | 低 | 中 | **最低** | 低 | **M** |

### 🏆 推荐方案：M方案2 精华 + Z方案1 结构 + D方案3 安全

**核心决策：**

1. **不自建 MCP Server** — win4r fork 已为 Hermes 准备好 CLI skill，零开发零维护
2. **CloakBrowser 只做认证** — notebooklm-py 80% 操作走 HTTP API，不需要浏览器
3. **CDP bridge 脚本** — 唯一需要自研的部分（~100行），从 CloakBrowser 提取 Cookie 写入 storage_state.json
4. **15分钟静默刷新** — cron job 定期执行 bridge 脚本 + NOTEBOOKLM_REFRESH_CMD 兜底
5. **版本锁定** — v0.3.4-hermes.4 审计标签，不拉 latest

---

## 二、架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        Hermes Agent                              │
│                                                                  │
│   ┌──────────────────────┐     ┌─────────────────────────────┐  │
│   │  cloakbrowsermcp     │     │  notebooklm CLI (skill)      │  │
│   │  MCP 工具             │     │  Shell 命令                   │  │
│   │                      │     │                              │  │
│   │  · cloak_launch      │     │  · notebooklm create         │  │
│   │  · cloak_navigate    │     │  · notebooklm source add     │  │
│   │  · cloak_type        │     │  · notebooklm generate audio │  │
│   │  · cloak_click       │     │  · notebooklm ask            │  │
│   │  · cloak_snapshot    │     │  · notebooklm download       │  │
│   │  · cloak_get_cookies │     │                              │  │
│   │                      │     │                              │  │
│   │  用途: Google 登录     │     │  用途: NotebookLM 全部操作    │  │
│   └──────────┬───────────┘     └──────────────┬──────────────┘  │
│              │                                │                 │
└──────────────┼────────────────────────────────┼─────────────────┘
               │ CDP                            │ HTTP API (protobuf)
               ▼                                ▼
     ┌──────────────────┐            ┌──────────────────────┐
     │   CloakBrowser    │  bridge    │  Google NotebookLM   │
     │   (stealth Chrome)│ ────────► │  (protobuf API)      │
     │                   │ cookies   │                      │
     │  · 49-57 C++ 补丁  │           │  · 创建 Notebook     │
     │  · humanize       │           │  · 添加来源           │
     │  · headless+Xvfb  │           │  · 聊天/问答          │
     └───────────────────┘           │  · 播客/视频/幻灯片    │
                                     └──────────────────────┘
```

---

## 三、快速安装

### 方式 A：一键脚本（推荐）

```bash
curl -fsSL https://your-domain.com/hermes-notebooklm/install.sh | bash
```

### 方式 B：手动安装

```bash
# 1. 确保 CloakBrowser 环境已就绪
ls ~/.hermes/skills/cloakbrowser/SKILL.md

# 2. 安装 notebooklm-py（win4r 审计版）
pip install "notebooklm-py[browser,cookies] @ git+https://github.com/win4r/notebooklm-py@v0.3.4-hermes.4"

# 3. 安装 Playwright Chromium（备用）
playwright install chromium

# 4. 安装 Hermes Skill
hermes skills tap add win4r/notebooklm-py
hermes skills install win4r/notebooklm-py/skills/notebooklm --force

# 5. 部署 Cookie 桥接脚本
cp scripts/cloak2nlm_bridge.py ~/hermes-browser/

# 6. 配置环境变量
echo 'NOTEBOOKLM_REFRESH_CMD="python3 ~/hermes-browser/cloak2nlm_bridge.py"' >> ~/.hermes/.env

# 7. 首次认证
# Hermes > "帮我登录 Google，我要用 NotebookLM"
# (CloakBrowser 自动登录 → bridge 提取 Cookie)

# 8. 验证
notebooklm auth check --test
hermes tools list | grep notebooklm
```

### 方式 C：Docker

```bash
cd docker/ && docker compose up -d
```

---

## 四、Skills 清单

| Skill | 文件 | 用途 |
|-------|------|------|
| 🔐 google-auth | `google-auth/SKILL.md` | CloakBrowser 登录 Google + Cookie 提取 |
| 📓 notebooklm | `notebooklm/SKILL.md` | NotebookLM 全功能（创建/来源/生成/下载） |
| 🔄 cookie-refresh | `cookie-refresh/SKILL.md` | 15分钟静默 Cookie 刷新 |

---

## 五、🔐 Cookie 桥接与15分钟静默刷新

### 桥接原理

```
CloakBrowser CDP (127.0.0.1:9222)
        │
        │ Network.getCookies
        ▼
cloak2nlm_bridge.py
        │
        │ CDP格式 → Playwright storage_state.json
        ▼
~/.notebooklm/profiles/default/storage_state.json
        │
        │ notebooklm-py 读取
        ▼
Google NotebookLM protobuf API
```

### 15分钟静默刷新机制

```yaml
三层保障:
  层1 — 定时刷新:
    cron job 每15分钟执行 bridge 脚本
    无论是否过期都刷新，确保 Cookie 始终新鲜

  层2 — 按需刷新:
    NOTEBOOKLM_REFRESH_CMD 环境变量
    notebooklm-py 遇到 401 时自动触发
    一次进程生命周期只触发一次（防循环）

  层3 — 持久化 Profile:
    CloakBrowser profile_dir 保存 Google 登录态
    即使 bridge 失败，CloakBrowser 仍保持登录
```

### Cron Job 配置

```bash
# 每15分钟静默刷新 Cookie
*/15 * * * * python3 ~/hermes-browser/cloak2nlm_bridge.py >> /tmp/nlm-cookie-refresh.log 2>&1
```

---

## 六、Hermes 配置

### ~/.hermes/config.yaml

```yaml
mcp_servers:
  # CloakBrowser — Google 登录用
  cloakbrowser:
    command: cloakbrowsermcp
    args: ["--caps", "all"]
    timeout: 120
    env:
      CLOAK_HEADLESS: "true"
      CLOAK_HUMANIZE: "true"
      CLOAK_PROFILE_DIR: "/data/cloak_profiles/google"

  # NotebookLM — 不需要 MCP，通过 skill 使用 CLI
  # Hermes skill 已安装: win4r/notebooklm-py/skills/notebooklm
```

### ~/.hermes/.env

```bash
# Cookie 自动刷新命令
NOTEBOOKLM_REFRESH_CMD="python3 ~/hermes-browser/cloak2nlm_bridge.py"

# NotebookLM 配置
NOTEBOOKLM_HOME="~/.notebooklm"
NOTEBOOKLM_PROFILE="default"
```

---

## 七、目录结构

```
hermes-notebooklm/
├── README.md                          # 本文档
├── CROSS_VALIDATION.md                # 四方案交叉验证
├── skills/
│   ├── google-auth/
│   │   └── SKILL.md                   # Google 登录 + Cookie 提取
│   ├── notebooklm/
│   │   └── SKILL.md                   # NotebookLM 全功能
│   └── cookie-refresh/
│       └── SKILL.md                   # 15分钟静默刷新
├── scripts/
│   ├── install.sh                     # 一键安装
│   ├── cloak2nlm_bridge.py            # Cookie 桥接脚本
│   └── setup_cron.sh                  # Cron 配置
├── config/
│   ├── hermes_config.yaml             # Hermes 配置模板
│   └── env.example                    # 环境变量模板
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── start.sh
└── docs/
    └── TROUBLESHOOTING.md
```

---

## 八、环境要求

| 项目 | 要求 |
|------|------|
| 系统 | Ubuntu 22.04+ ARM64 |
| 内存 | ≥ 2GB |
| Python | 3.10+ |
| 前置 | Hermes Agent + cloakbrowsermcp 已安装 |
| 网络 | 可访问 Google 和 NotebookLM |

---

## 九、License

MIT
