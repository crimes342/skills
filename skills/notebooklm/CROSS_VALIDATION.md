# 四方案交叉验证报告 — NotebookLM 适配

## 验证日期：2026-05-11

---

## 1. 方案概要

### D方案3
- **核心思路**：双 MCP 通道（cloakbrowsermcp + notebooklm_mcp），Hermes 上层调度
- **仓库选型**：win4r fork（v0.3.4-hermes.4 审计标签）
- **认证策略**：--browser-cookies chrome + NOTEBOOKLM_REFRESH_CMD 自动刷新
- **特点**：最详细的配置矩阵和安全审计说明

### G方案4
- **核心思路**："重装破防，轻装突击" — Browser Auth + API Action
- **仓库选型**：融合 teng-lin + win4r 两家之长
- **认证策略**：CloakBrowser 登录 → 提取 Cookie → notebooklm-mcp 接管
- **特点**：强调 CloakBrowser 的 C++ 级反检测优势

### M方案2
- **核心思路**：CloakBrowser 只做认证，notebooklm-py CLI skill 做业务，bridge.py 桥接
- **仓库选型**：win4r fork（CLI skill 方式，不自建 MCP）
- **认证策略**：CDP bridge 脚本（~80行）+ NOTEBOOKLM_REFRESH_CMD
- **特点**：自研代码量最小，架构最轻

### Z方案1
- **核心思路**：独立 notebooklm skill 与 cloakbrowser skill 平级，共享认证
- **仓库选型**：win4r fork（锁定审计版本）
- **认证策略**：cloak_get_cookies → storage_state.json / NOTEBOOKLM_AUTH_JSON
- **特点**：目录结构最规范，解耦最彻底

---

## 2. 逐维度验证

### 2.1 仓库选型

| 方案 | 选择 | Hermes 适配 | 安全审计 | Cookie 自动刷新 | 判定 |
|------|------|-------------|----------|----------------|------|
| D | win4r fork | ✅ skills/notebooklm/ 布局 | ✅ SECURITY_AUDIT.md | ✅ PR#298 | ✅ |
| G | 融合两家 | ❌ 需自研 MCP | ❌ | ❌ | ❌ |
| M | win4r fork | ✅ CLI skill | ✅ | ✅ PR#298 | ✅ |
| Z | win4r fork | ✅ | ✅ | ✅ | ✅ |

**结论**：win4r fork 是唯一正确选择。G方案融合两家意味着自建 MCP Server，维护负担大。

### 2.2 架构模式

| 方案 | 模式 | 自研代码量 | 维护风险 | 灵活性 | 判定 |
|------|------|-----------|----------|--------|------|
| D | 双 MCP 通道 | 配置为主 | 低 | 高 | ✅ |
| G | 自建 MCP Server | ~200行 | 高 | 高 | ❌ |
| M | CLI Skill | ~80行 bridge | **最低** | 高 | ✅✅ |
| Z | 独立 Skill | 配置为主 | 低 | 高 | ✅ |

**结论**：M方案的 CLI Skill 模式最优。notebooklm-py 已有完整 CLI，不需要再封装 MCP。

### 2.3 认证与 Cookie 桥接

| 方案 | 桥接方式 | 可靠性 | ARM64 兼容 | 判定 |
|------|----------|--------|-----------|------|
| D | --browser-cookies chrome | 中（需本地浏览器） | ❌ 无头服务器无 Chrome | ⚠️ |
| G | 自研 MCP 工具 | 中 | ✅ | ⚠️ |
| M | CDP bridge.py | **高** | ✅ | ✅✅ |
| Z | cloak_get_cookies 直接写入 | 高 | ✅ | ✅ |

**结论**：M方案的 CDP bridge 最可靠。CDP 是 CloakBrowser 的标准接口，无需本地浏览器数据库。

### 2.4 Cookie 刷新策略

| 方案 | 定时刷新 | 按需刷新 | 15分钟间隔 | 判定 |
|------|----------|----------|-----------|------|
| D | ❌ | ✅ REFRESH_CMD | ❌ | ⚠️ |
| G | ❌ | ✅ 手动 | ❌ | ❌ |
| M | ✅ cron | ✅ REFRESH_CMD | ✅ | ✅✅ |
| Z | ❌ | ✅ REFRESH_CMD | ❌ | ⚠️ |

**结论**：M方案是唯一同时支持定时+按需双模式的。用户要求15分钟静默刷新，M方案的 cron + REFRESH_CMD 组合完美匹配。

---

## 3. 关键分歧裁决

### 分歧 1：自建 MCP Server vs 用 CLI Skill

- **D/G**：自建 MCP Server 封装 notebooklm-py
- **M/Z**：用 CLI Skill 直接调用 notebooklm 命令

**裁决**：CLI Skill。理由：
1. notebooklm-py 已有完整 CLI，覆盖所有功能
2. win4r fork 已为 Hermes 准备好 SKILL.md
3. 自建 MCP = 重复造轮子，且需要跟进上游 API 变化

### 分歧 2：Cookie 桥接方式

- **D**：--browser-cookies chrome（需要本地 Chrome）
- **M**：CDP bridge.py（从 CloakBrowser CDP 提取）
- **Z**：cloak_get_cookies 直接写入

**裁决**：CDP bridge.py。理由：
1. ARM64 无头服务器没有本地 Chrome，--browser-cookies 不可用
2. CDP 是 CloakBrowser 标准接口，稳定可靠
3. bridge.py 可同时被 cron 和 REFRESH_CMD 调用

### 分歧 3：CloakBrowser 的职责边界

- **G**：CloakBrowser 同时负责登录和 API 操作
- **M/Z**：CloakBrowser 只负责登录，API 操作走 HTTP

**裁决**：CloakBrowser 只做登录。理由：
1. notebooklm-py 80% 操作走 protobuf HTTP API，不需要浏览器
2. 浏览器操作 NotebookLM 页面 = 用大炮打蚊子，且 UI 变化就要改代码
3. HTTP API 比浏览器自动化快 10 倍以上

---

## 4. 最终融合方案

```
采用: M方案2 架构 + Z方案1 目录结构 + D方案3 安全审计

架构: CloakBrowser(认证) + notebooklm-py CLI(业务) + bridge.py(桥接)
仓库: win4r/notebooklm-py@v0.3.4-hermes.4
技能: Hermes Skill (CLI方式, 不自建MCP)
刷新: cron(15分钟) + REFRESH_CMD(按需) 双模式
安全: 锁定审计标签, storage_state.json 权限 0o600
```
