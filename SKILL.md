# Daily News Briefing Skill

生成每日新闻简报：Polymarket 预测市场扫描 + 多领域新闻搜索 + 结构化报告。

## 触发条件

用户说"每日新闻"、"新闻简报"、"daily news"、"news briefing"或类似关键词时触发。
也适用于 cron 定时任务（payload.kind = agentTurn）。

## 执行流程

### 第一步：Polymarket 扫描器

运行扫描器脚本，获取预测市场数据：

```bash
node <SKILL_DIR>/scripts/polymarket-scanner.mjs
```

脚本输出：
- **stdout**：人类可读的文本报告（可直接展示）
- **stderr**：运行日志
- **JSON 文件**：`/tmp/polymarket-scan.json`（默认路径，可用 `--json` 修改）

读取 JSON 文件获取结构化数据，用于后续报告生成。

> **扫描器零外部依赖**，仅需 Node.js >= 18。使用 Polymarket Gamma API（公开、无需密钥）。
> 链接格式：`https://polymarket.com/event/{slug}`（slug 取自 `event.slug`，非 `market.slug`）

### 第二步：新闻搜索

使用 agent 自带的 web search 能力搜索以下领域（每个领域至少一次搜索）：

| 领域 | 推荐搜索词 |
|------|-----------|
| 地缘时政 | `geopolitics news today`, `international politics news today` |
| 财经市场 | `global stock market today`, `crypto market today`, `central bank decision today` |
| Edge Tech | `quantum computing breakthrough 2026`, `frontier technology news` |
| AI 动态 | `AI news today`, `large language model update 2026` |

> **重要**：搜索词可按当前热点调整，以上仅为默认建议。

### 第三步：生成报告

#### 🎰 Polymarket 专项
- 使用扫描器 JSON 中的 `items` 数组
- 分类展示：临近到期异常 + 热门市场异常
- 链接格式：`https://polymarket.com/event/{slug}`（取自 `item.url`）
- 基于 `item.analysis` 做简要解读

#### 📰 新闻简报
每个领域 2-5 条，每条格式：
- **[{emoji}重要程度] 标题**
- 摘要（2-3 句话）
- 💡 解读（一句话）
- 🔗 [来源]({搜索结果原始 URL})

重要程度：🔴重大 / 🟡关注 / 🟢了解

#### 📌 今日看点
3-5 句话总结全天要点。

## 关键规则

1. **URL 必须来自搜索结果原文**，禁止编造或修改
2. **无结果时写「今日暂无重大报道」**，不要编造
3. **不要编造数字**，只引用搜索结果中的数据

## 依赖

| 组件 | 依赖 |
|------|------|
| Polymarket 扫描器 | Node.js >= 18（零 npm 依赖） |
| 新闻搜索 | Agent 自带 web search |
| 报告生成 | Agent 模型能力 |

## Cron 用法

```json
{
  "kind": "agentTurn",
  "message": "每日新闻简报时间到了。请执行 daily-news skill。",
  "timeoutSeconds": 300
}
```
