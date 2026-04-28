# Market Whale Alert 🐋

跨市场巨鲸异动监控系统。适配任意 AI Agent 及任意搜索/推送能力。

## 架构设计

```
┌─────────────────────────────────────────────┐
│              Agent (任意模型)                 │
│  ┌─────────┐  ┌──────────┐  ┌─────────────┐ │
│  │ 数据采集 │  │ 异常检测 │  │ 报告生成    │ │
│  │ (脚本)   │  │ (脚本)   │  │ (Agent能力) │ │
│  └────┬─────┘  └────┬─────┘  └──────┬──────┘ │
│       │              │               │        │
│  ┌────▼──────────────▼───────────────▼─────┐  │
│  │         统一 JSON 中间层                 │  │
│  │  /tmp/market-whale-{date}-{time}.json   │  │
│  └─────────────────────────────────────────┘  │
│       │                                       │
│  ┌────▼─────────────────────────────────────┐ │
│  │  推送层 (Agent 自带能力: 消息/频道/通知) │ │
│  └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## 核心原则

- **零依赖**：仅需 Node.js >= 18，无 npm 包
- **零密钥**：全部使用公开 API
- **模型无关**：脚本输出结构化 JSON，任意模型均可解读
- **搜索无关**：脚本直接采集数据，不依赖特定搜索工具
- **推送无关**：输出文件 + stdout，Agent 自行决定推送渠道

## 触发条件

用户说「巨鲸监控」「whale alert」「大额异动」「市场异动」或类似关键词时触发。

## 文件结构

```
scripts/
├── polymarket-whale.mjs    # Polymarket 巨额下注扫描
├── crypto-whale.mjs        # 加密市场巨鲸追踪
├── futures-alert.mjs       # 期货期权异动扫描
├── commodity-scanner.mjs   # 🆕 大宗商品 + 股指 + 国债 + 外汇
├── daily-summary.mjs       # 上一日异常总结生成
└── scheduler.mjs           # 智能调度器（判断推送频率）
```

## 执行模式

### 模式一：手动触发（用户请求）

用户说「巨鲸监控」→ 运行三个扫描器 → 生成报告 → 推送

```bash
node <SKILL_DIR>/scripts/polymarket-whale.mjs --json /tmp/poly-whale.json
node <SKILL_DIR>/scripts/crypto-whale.mjs --json /tmp/crypto-whale.json
node <SKILL_DIR>/scripts/futures-alert.mjs --json /tmp/futures-whale.json
```

Agent 读取三个 JSON 文件，汇总生成人类可读报告。

### 模式二：每日晨报（上一日总结）

用户设置 cron 或手动触发 → 生成前一日异常总结

```bash
node <SKILL_DIR>/scripts/daily-summary.mjs --date yesterday --json /tmp/daily-summary.json
```

输出包含：
- 前一日所有 Critical/High 信号汇总
- 各市场最大单笔异动
- 跨市场关联分析（如 Polymarket 大额下注 vs 加密市场波动）
- 生成日期范围内的异常趋势

### 模式三：智能定时监控（核心功能）

#### 调度逻辑

```bash
node <SKILL_DIR>/scripts/scheduler.mjs
```

调度器输出建议的下次执行时间和推送级别：

```
{
  "nextRun": "2026-04-28T15:20:00Z",
  "interval": "5m",          // 5m | 15m | 1h
  "urgency": "critical",     // critical | high | normal
  "reasons": [
    "BTC期权4h内到期 ($27.2B)",
    "ZKJUSDT资金费率-1.74% (Critical)",
    "美联储决议17h内到期 ($195.9M)"
  ]
}
```

#### 智能频率规则

| 条件 | 推送间隔 | 推送级别 |
|------|---------|---------|
| 任意市场 ≤ 1h 内到期/交割 | **5 分钟** | 🚨 Critical |
| 任意市场 ≤ 6h 内到期 + 成交量 > $10M | **15 分钟** | ⚠️ High |
| 任意市场 ≤ 24h 内到期 + 成交量 > $1M | **30 分钟** | 📌 Normal |
| 交易时段（主要市场开盘） | **1 小时** | 📊 Routine |
| 非交易时段 + 无紧急信号 | **4 小时** | 💤 Low |

#### 交易时段定义

| 市场 | 开盘时间 (UTC) | 收盘时间 (UTC) |
|------|---------------|---------------|
| 美股/期货 | 13:30 | 20:00 |
| 欧股 | 08:00 | 16:30 |
| 亚洲股市 | 00:00 | 08:00 |
| 加密货币 | 24/7 | 24/7 |
| Polymarket | 24/7 | 24/7 |

#### Cron 配置示例

**主监控（每小时，Agent 自动判断是否需要加速）：**
```json
{
  "kind": "agentTurn",
  "message": "执行巨鲸异动扫描。读取 /tmp/market-whale-scheduler.json 获取调度建议，按建议频率执行。如无异常信号则回复 HEARTBEAT_OK。",
  "timeoutSeconds": 180
}
```

**每日晨报（每天早8点）：**
```json
{
  "schedule": { "kind": "cron", "expr": "0 8 * * *", "tz": "Asia/Shanghai" },
  "payload": { "kind": "agentTurn", "message": "生成前一日市场异常总结报告。运行 daily-summary.mjs 并推送。", "timeoutSeconds": 120 },
  "sessionTarget": "isolated"
}
```

## 报告格式（Agent 生成模板）

### 实时异动报告

```
🐋 巨鲸异动 | {时间}
═══════════════════════════════════

🚨 [Critical] {信号描述}
   市场: {市场名} | 类型: {类型}
   数据: {关键数值}
   解读: {一句话分析}
   链接: {URL}

⚠️ [High] {信号描述}
   ...

📊 本次扫描: {N}个信号 (Critical:{n1} High:{n2})
⏰ 下次扫描: {时间} ({原因})
```

### 每日晨报

```
📋 市场异常日报 | {日期}
═══════════════════════════════════

📊 昨日统计
   总信号: {N} | Critical: {n1} | High: {n2}
   最活跃市场: {市场名} ({信号数})

🎰 Polymarket 异常 Top 5
   1. {标题} — {成交量} — {关键信号}
   ...

₿ 加密市场异动 Top 5
   1. {币种} — {变化%} — {原因}
   ...

📈 期货期权异动 Top 5
   1. {合约} — {信号} — {解读}
   ...

🔗 跨市场关联
   {如: Polymarket美联储决议$196M + 期货资金费率偏空 = ...}

📌 今日关注
   {3-5 个即将到来的关键时间节点}
```

## 数据源一览

| 模块 | API | 需要密钥 | 限流 |
|------|-----|---------|------|
| Polymarket | gamma-api.polymarket.com | ❌ | 宽松 |
| BTC链上 | blockchain.info | ❌ | 中等 |
| ETH链上 | api.etherscan.io | ❌ (免费tier) | 5次/s |
| 市场行情 | api.coingecko.com | ❌ | 10次/min |
| 期货数据 | fapi.binance.com | ❌ | 1200次/min |
| 期权数据 | deribit.com/api/v2 | ❌ | 宽松 |

## Agent 集成指南

本技能不依赖任何特定工具。Agent 需要具备：

1. **执行脚本能力**：运行 Node.js 脚本
2. **读取文件能力**：读取 JSON 输出
3. **定时任务能力**：设置 cron 或类似调度
4. **消息推送能力**：将报告推送给用户（可选）

### 适配不同 Agent

| Agent 平台 | 数据采集 | 定时任务 | 推送方式 |
|-----------|---------|---------|---------|
| OpenClaw | exec + read | cron 工具 | 消息渠道 |
| AutoGPT | subprocess | 内置循环 | stdout |
| LangChain | tool | scheduler | callback |
| Dify | HTTP 请求 | 外部 cron | webhook |
| 通用 Agent | shell exec | 外部 cron | 文件/API |

## 阈值参考

见各脚本文件头部 CONFIG 对象，可按需调整。
