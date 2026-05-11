# Hermes Agent — CloakBrowser 反爬自动化套件

> **Hermes → MCP → CloakBrowser** 三层架构，在 Oracle Cloud ARM64 Ubuntu 无 GPU 服务器上实现隐身浏览器自动化。

---

## 一、四方案交叉验证结论

| 维度 | D方案 | G方案 | M方案 | Z方案 | **综合最优** |
|------|-------|-------|-------|-------|-------------|
| MCP 实现 | 用官方 `cloakbrowsermcp` | 自研 Node.js MCP Server | 自研 Python MCP Server (300+行) | 用官方 `cloakbrowsermcp` | **D/Z** — 官方包维护成本为零 |
| 反检测策略 | headless=True | headed + Xvfb | headless + Xvfb | 两种模式可选 | **Z** — 按站点强度灵活切换 |
| 代码量 | 配置为主 | ~200行 TS | ~500行 Python | 配置为主 | **D/Z** — 最小代码量 |
| ARM64 适配 | ✅ 原生 | ⚠️ 需确认 | ✅ 原生 | ✅ 原生 | **D/Z** |
| Docker 支持 | ✅ 有 | ✅ 有 | ✅ 完整 compose | ✅ 有 | **M** — 最完整 |
| 复合登录工具 | ❌ 需手动编排 | ❌ 需手动编排 | ✅ `browser_login` 一步完成 | ❌ 需手动编排 | **M** — 但过度工程化 |
| 安全实践 | 一般 | 一般 | 较好 | ✅ 最全面 | **Z** |
| 维护风险 | 低 | 高（自研） | 高（自研） | 低 | **D/Z** |

### 🏆 推荐方案：D + Z 融合 + M 精华

**核心决策：**
1. **MCP 层** → 采用官方 `cloakbrowsermcp`（D/Z 方案），不自研（G/M 方案维护负担大）
2. **反爬模式** → 双模式可选：纯 headless（一般站点）/ headed + Xvfb（强反爬站点）（Z 方案）
3. **Skills 封装** → 吸取 M 方案的 `browser_login` 复合工具思路，封装为 Hermes Skills
4. **部署方式** → Docker + systemd 双轨（M 方案的 compose + D 方案的 systemd）
5. **安全加固** → 采用 Z 方案的安全最佳实践

---

## 二、快速安装

### 方式 A：一键脚本（推荐）

```bash
curl -fsSL https://your-domain.com/hermes-cloak/install.sh | bash
```

### 方式 B：手动安装

```bash
# 1. 系统依赖
sudo apt update && sudo apt install -y \
  python3 python3-pip python3-venv \
  libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
  libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
  libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
  xvfb fonts-noto-color-emoji fonts-freefont-ttf fonts-unifont

# 2. Python 环境
python3 -m venv ~/hermes-cloak/.venv
source ~/hermes-cloak/.venv/bin/activate
pip install cloakbrowser cloakbrowsermcp

# 3. 验证
python -m cloakbrowser info
cloakbrowsermcp --help
```

### 方式 C：Docker

```bash
cd docker/
docker compose up -d
```

---

## 三、Hermes 配置

编辑 `~/.hermes/config.yaml`：

```yaml
mcp_servers:
  cloakbrowser:
    command: cloakbrowsermcp
    args: ["--caps", "all"]
    timeout: 120
    env:
      CLOAK_HEADLESS: "true"           # ARM64 无 GPU
      CLOAK_HUMANIZE: "true"           # 人类行为模拟
      CLOAK_PROXY: ""                  # 可选：住宅代理
      CLOAK_PROFILE_DIR: "/data/cloak_profiles"  # 持久化登录
```

重启 Hermes 后验证：

```bash
hermes restart
hermes tools list | grep cloak
```

---

## 四、Skills 清单

本套件提供 7 个 Hermes Skills，位于 `skills/` 目录：

| Skill | 文件 | 用途 |
|-------|------|------|
| 🔧 browser-lifecycle | `browser-lifecycle/SKILL.md` | 启动/关闭浏览器实例 |
| 🧭 navigation | `navigation/SKILL.md` | 页面导航、前进后退 |
| 👆 interaction | `interaction/SKILL.md` | 点击、悬停、键盘操作 |
| ⌨️ typing | `typing/SKILL.md` | 逐键输入 vs 快速填充 |
| 📸 screenshot | `screenshot/SKILL.md` | 截图与页面快照 |
| 🍪 cookies | `cookies/SKILL.md` | Cookie 读写与会话管理 |
| 🔐 **login** | **`login/SKILL.md`** | **复合登录技能（核心）** |

安装 Skills：

```bash
cp -r skills/* ~/.hermes/skills/
hermes skills reload
```

---

## 五、🔐 登录技能模板（实战级）

> 以下是 Hermes Agent 可直接使用的「登录技能」自然语言提示词 + 工具调用顺序。

### 场景：标准网站登录

**用户指令（自然语言）：**
```
用 CloakBrowser 登录 https://example.com/login
用户名: admin@example.com
密码: P@ssw0rd123
```

**Hermes 内部执行链：**

```
Step 1: cloak_launch
  ├─ headless=true（或 false + Xvfb 强反爬模式）
  ├─ humanize=true
  └─ profile_dir="/data/cloak_profiles/site_x"  # 持久化

Step 2: cloak_navigate(pid, "https://example.com/login")
  └─ 等待 domcontentloaded

Step 3: cloak_snapshot(pid)
  └─ 获取页面无障碍树，识别交互元素
  └─ 输出: [@e1]=用户名输入框, [@e2]=密码输入框, [@e3]=登录按钮

Step 4: cloak_type(pid, "@e1", "admin@example.com")
  ├─ delay=80ms/字符（模拟真人打字节奏）
  └─ 先 click 再 type（对 reCAPTCHA 友好）

Step 5: cloak_type(pid, "@e2", "P@ssw0rd123")
  ├─ delay=60ms/字符
  └─ 密码输入略快于用户名（人类行为特征）

Step 6: cloak_click(pid, "@e3")
  └─ 贝塞尔曲线鼠标轨迹（humanize=True）

Step 7: cloak_wait_for_navigation(pid)
  └─ 等待页面跳转完成，timeout=30s

Step 8: cloak_snapshot(pid)
  └─ 验证登录结果
  └─ 检查是否出现 dashboard / welcome / logout 等成功标志

Step 9: cloak_get_cookies(pid)
  └─ 保存会话 Cookie 供后续复用

Step 10: cloak_screenshot(pid)
  └─ 截取登录后页面，存档备查
```

### 关键策略说明

```yaml
反检测策略:
  逐键输入: 用 cloak_type 而非 cloak_fill，对 reCAPTCHA 更友好
  人类节奏: 用户名 delay=80ms，密码 delay=60ms，间隔 0.3-0.5s
  贝塞尔曲线: 鼠标移动使用贝塞尔曲线而非直线
  持久化 profile: 保存登录状态，下次免登录
  指纹隔离: 每个站点使用不同 fingerprint_seed

强反爬站点升级策略:
  headed + Xvfb: 启动 Xvfb 虚拟显示，headless=false
  住宅代理: 使用住宅 IP 代理 + geoip=True 时区匹配
  预热 profile: 首次访问先浏览其他页面再登录
```

### Hermes 提示词模板（可直接粘贴到 SKILL.md）

```markdown
## 登录技能 — Hermes Agent 提示词

你是一个浏览器自动化专家。当用户要求登录某个网站时，按以下流程执行：

### 执行步骤

1. **启动浏览器**
   调用 cloak_launch，参数：
   - headless: true（默认）或 false（强反爬站点 + Xvfb）
   - humanize: true（必须开启）
   - profile_dir: 按目标站点命名，如 "/data/cloak_profiles/{domain}"

2. **导航到登录页**
   调用 cloak_navigate，URL 为用户提供的登录地址

3. **获取页面快照**
   调用 cloak_snapshot，分析无障碍树，识别：
   - 用户名输入框（通常为 input[type=text/email] 或包含 "user/email/账号" 的元素）
   - 密码输入框（input[type=password]）
   - 登录按钮（button[type=submit] 或包含 "登录/login/sign in" 的元素）

4. **输入凭据**
   - 先 click 用户名输入框，再 cloak_type 输入用户名，delay=80
   - 等待 0.3 秒（cloak_sleep(0.3)）
   - 先 click 密码输入框，再 cloak_type 输入密码，delay=60
   - 等待 0.5 秒

5. **提交登录**
   调用 cloak_click 点击登录按钮

6. **等待与验证**
   - cloak_wait_for_navigation 等待页面加载
   - cloak_snapshot 获取新页面结构
   - 判断是否登录成功（检查 URL 变化、欢迎文本、错误提示）

7. **保存会话**
   - cloak_get_cookies 保存 Cookie
   - cloak_screenshot 存档截图

### 异常处理

- 如果页面出现验证码（CAPTCHA），截图并通知用户手动处理
- 如果登录失败，截图当前页面，分析错误信息并报告
- 如果页面加载超时，重试一次（最多 3 次）
- 如果被反爬拦截，建议切换 headed + Xvfb 模式或更换代理

### 输出格式

登录完成后，向用户报告：
- ✅/❌ 登录状态
- 当前页面 URL 和标题
- 获取到的 Cookie 数量
- 截图路径（如有）
```

---

## 六、目录结构

```
hermes-agent/
├── README.md                    # 本文档
├── CROSS_VALIDATION.md          # 四方案交叉验证详细报告
├── skills/                      # Hermes Skills
│   ├── browser-lifecycle/
│   │   └── SKILL.md
│   ├── navigation/
│   │   └── SKILL.md
│   ├── interaction/
│   │   └── SKILL.md
│   ├── typing/
│   │   └── SKILL.md
│   ├── screenshot/
│   │   └── SKILL.md
│   ├── cookies/
│   │   └── SKILL.md
│   └── login/
│       └── SKILL.md             # 核心：登录技能
├── scripts/
│   ├── install.sh               # 一键安装脚本
│   ├── start_xvfb.sh            # Xvfb 虚拟显示启动
│   └── setup_hermes_config.sh   # Hermes 配置生成
├── config/
│   ├── hermes_config.yaml       # Hermes 配置模板
│   └── env.example              # 环境变量模板
├── docker/
│   ├── Dockerfile               # ARM64 Docker 镜像
│   ├── docker-compose.yml       # 完整编排
│   └── start.sh                 # 容器启动脚本
└── docs/
    └── TROUBLESHOOTING.md       # 故障排查手册
```

---

## 七、环境要求

| 项目 | 要求 |
|------|------|
| 系统 | Ubuntu 22.04+ ARM64 (aarch64) |
| 内存 | ≥ 2GB（建议 4GB+） |
| 磁盘 | ≥ 2GB 可用空间 |
| Python | 3.10+ |
| 网络 | 可访问 PyPI 和目标网站 |

---

## 八、快速验证

```bash
# 1. 验证 CloakBrowser 安装
python3 -c "from cloakbrowser import launch; b = launch(headless=True); print('OK'); b.close()"

# 2. 验证 MCP Server
cloakbrowsermcp --caps all &  # 后台启动
sleep 3 && kill %1            # 确认无报错

# 3. 验证 Hermes 连接
hermes tools list | grep cloak
# 应输出: cloak_launch, cloak_navigate, cloak_snapshot, cloak_click, cloak_type ...
```

---

## 九、License

MIT — 自由使用、修改和分发。
