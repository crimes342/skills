#!/bin/bash
# daily-news skill 安装脚本
# 用法：bash install.sh [目标workspace路径]
#
# 示例：
#   bash install.sh                              # 安装到 ~/.openclaw/workspace
#   bash install.sh /path/to/other/workspace     # 安装到指定 workspace

set -e

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
SKILL_DIR="$WORKSPACE/skills/daily-news"

echo "📦 安装 daily-news skill → $SKILL_DIR"

mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/templates"

# ── 写入 SKILL.md ──
cat > "$SKILL_DIR/SKILL.md" << 'SKILL_EOF'
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
SKILL_EOF

# ── 写入扫描器 ──
cat > "$SKILL_DIR/scripts/polymarket-scanner.mjs" << 'SCANNER_EOF'
#!/usr/bin/env node
/**
 * Polymarket Scanner v2 — Daily News Skill
 * 零外部依赖，Node.js >= 18 + fetch API
 * 用法：node polymarket-scanner.mjs [--hours 72] [--json /tmp/polymarket-scan.json]
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    hours:  { type: 'string', default: '72' },
    json:   { type: 'string', default: '/tmp/polymarket-scan.json' },
    max:    { type: 'string', default: '30' },
  },
  strict: false,
});

const GAMMA_API = 'https://gamma-api.polymarket.com';
const CONFIG = {
  hoursUntilExpiry: Number(args.hours),
  anomalyVolumeRatio: 5,
  priceExtremeThreshold: 0.9,
  maxResults: Number(args.max),
  jsonOutput: args.json,
};

async function fetchJSON(url) {
  const resp = await fetch(url, { headers: { 'Accept': 'application/json' } });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${url}`);
  return resp.json();
}
function hoursUntil(d) { return (new Date(d).getTime() - Date.now()) / 3600000; }
function fmtPct(p) { return (parseFloat(p)*100).toFixed(1)+'%'; }
function fmtMoney(n) { n=Number(n); return n>=1e6?`$${(n/1e6).toFixed(1)}M`:n>=1e3?`$${(n/1e3).toFixed(0)}K`:`$${n.toFixed(0)}`; }

function detectAnomalies(event) {
  const signals=[], vol=Number(event.volume||0), liq=Number(event.liquidity||0), hrs=hoursUntil(event.endDate);
  for (const m of (event.markets||[])) {
    const prices=JSON.parse(m.outcomePrices||'[]'), outcomes=JSON.parse(m.outcomes||'[]');
    for (let i=0;i<prices.length;i++) if (parseFloat(prices[i])>=CONFIG.priceExtremeThreshold)
      signals.push({type:'PRICE_EXTREME',severity:'high',detail:`${outcomes[i]}=${fmtPct(prices[i])}`});
  }
  if (liq>0&&vol/liq>CONFIG.anomalyVolumeRatio) signals.push({type:'VOLUME_SPIKE',severity:'high',detail:`量/流动性=${(vol/liq).toFixed(1)}x`});
  if (hrs<24&&vol>1e5) signals.push({type:'HIGH_VOLUME_NEAR_EXPIRY',severity:'medium',detail:`24h内到期 ${fmtMoney(vol)}`});
  return signals;
}

function generateAnalysis(event) {
  const markets=event.markets||[], hrs=hoursUntil(event.endDate), vol=Number(event.volume||0), liq=Number(event.liquidity||0);
  let leading={outcome:'?',price:0};
  for (const m of markets) { const p=JSON.parse(m.outcomePrices||'[]'),o=JSON.parse(m.outcomes||'[]'); for(let i=0;i<p.length;i++) if(parseFloat(p[i])>leading.price) leading={outcome:o[i],price:parseFloat(p[i])}; }
  const parts=[];
  if(hrs<24)parts.push(`${hrs.toFixed(0)}h内到期`);
  if(liq>0&&vol/liq>10)parts.push(`资金活跃(${(vol/liq).toFixed(1)}x)`);
  if(leading.price>.95)parts.push(`${leading.outcome}几乎确定(${fmtPct(String(leading.price))})`);
  else if(leading.price>.6)parts.push(`${leading.outcome}领先(${fmtPct(String(leading.price))})`);
  else if(leading.price>0)parts.push(`${leading.outcome}微幅领先(${fmtPct(String(leading.price))})`);
  if(vol>1e5)parts.push(`总成交量${fmtMoney(vol)}`);
  return parts.join('；');
}

async function getExpiringEvents() {
  const now=new Date().toISOString(), cutoff=new Date(Date.now()+CONFIG.hoursUntilExpiry*3600000).toISOString();
  return fetchJSON(`${GAMMA_API}/events?`+new URLSearchParams({active:'true',closed:'false',limit:String(CONFIG.maxResults),order:'end_date_min',ascending:'true',end_date_min:now,end_date_max:cutoff}));
}
async function getTrendingEvents() {
  return fetchJSON(`${GAMMA_API}/events?`+new URLSearchParams({active:'true',closed:'false',limit:'15',order:'volume',ascending:'false'}));
}

function formatEventReport(event, signals) {
  const hrs=hoursUntil(event.endDate), url=`https://polymarket.com/event/${event.slug}`, analysis=generateAnalysis(event);
  const lines=[`📌 ${event.title}`,`   到期: ${new Date(event.endDate).toISOString().replace('T',' ').slice(0,16)} UTC (${hrs.toFixed(1)}h)`,`   成交量: ${fmtMoney(event.volume)} | 流动性: ${fmtMoney(event.liquidity)}`];
  for(const m of(event.markets||[])){const o=JSON.parse(m.outcomes||'[]'),p=JSON.parse(m.outcomePrices||'[]');lines.push(`   赔率: ${o.map((x,i)=>`${x}:${fmtPct(p[i])}`).join(' | ')}`);}
  if(signals.length)lines.push(`   🚨 ${signals.map(s=>s.detail).join('; ')}`);
  lines.push(`   💡 ${analysis}`,`   🔗 ${url}`);
  return lines.join('\n');
}

function buildItem(r,cat){return{title:r.event.title,slug:r.event.slug,url:`https://polymarket.com/event/${r.event.slug}`,endDate:r.event.endDate,volume:r.event.volume,liquidity:r.event.liquidity,markets:(r.event.markets||[]).map(m=>({question:m.question,outcomes:JSON.parse(m.outcomes||'[]'),prices:JSON.parse(m.outcomePrices||'[]')})),signals:r.signals,analysis:generateAnalysis(r.event),category:cat};}

async function main() {
  console.error(`🎰 Polymarket Scanner v2 | ${new Date().toISOString()}`);
  const [expiring,trending]=await Promise.all([getExpiringEvents(),getTrendingEvents()]);
  const expR=expiring.map(e=>({event:e,signals:detectAnomalies(e),get hasAnomaly(){return this.signals.length>0}}));
  const trR=trending.map(e=>({event:e,signals:detectAnomalies(e)})).filter(r=>r.signals.length>0);
  const anom=expR.filter(r=>r.hasAnomaly), norm=expR.filter(r=>!r.hasAnomaly);

  console.log(`📊 临近到期: ${expiring.length} | 热门: ${trending.length} | 异常: ${anom.length}\n`);
  if(anom.length){console.log('='.repeat(60)+'\n🚨 临近到期+异常\n'+'='.repeat(60));for(const{event,signals}of anom){console.log(formatEventReport(event,signals));console.log('');}}
  if(norm.length){console.log('='.repeat(60)+'\n⏰ 即将到期(无异常)\n'+'='.repeat(60));for(const{event}of norm.slice(0,10)){console.log(formatEventReport(event,[]));console.log('');}}
  if(trR.length){console.log('='.repeat(60)+'\n🔥 热门市场异常\n'+'='.repeat(60));for(const{event,signals}of trR.slice(0,10)){console.log(formatEventReport(event,signals));console.log('');}}

  const summary={scanTime:new Date().toISOString(),expiringCount:expiring.length,trendingCount:trending.length,anomalyCount:anom.length+trR.length,items:[...anom.map(r=>buildItem(r,'expiring_anomaly')),...trR.map(r=>buildItem(r,'trending_anomaly'))]};
  writeFileSync(CONFIG.jsonOutput,JSON.stringify(summary,null,2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}
main().catch(e=>{console.error('❌',e.message);process.exit(1);});
SCANNER_EOF

# ── 写入报告模板 ──
cat > "$SKILL_DIR/templates/report.md" << 'TPL_EOF'
# 📋 每日新闻简报 | {{date}} {{weekday}}

## 🎰 Polymarket 专项
### 🚨 临近到期 + 异常信号
{{#each expiring_anomalies}}
**📌 {{title}}**
- 赔率：{{#each markets}}{{outcome}}: {{price}} {{/each}}
- 到期：{{endDate}} ({{hoursLeft}}h)
- 异常：{{#each signals}}{{detail}}; {{/each}}
- 💡 {{analysis}}
- 🔗 {{url}}
{{/each}}

## 📰 新闻简报
### 🌍 地缘时政 / 💰 财经市场 / 🔬 前沿科技 / 🤖 AI 动态
（每个领域 2-5 条，附原始 URL）

## 📌 今日看点
（3-5 句总结）
TPL_EOF

chmod +x "$SKILL_DIR/scripts/polymarket-scanner.mjs"

echo ""
echo "✅ daily-news skill 已安装到: $SKILL_DIR"
echo ""
echo "📁 文件:"
echo "   $SKILL_DIR/SKILL.md"
echo "   $SKILL_DIR/scripts/polymarket-scanner.mjs"
echo "   $SKILL_DIR/templates/report.md"
echo ""
echo "🧪 验证: node $SKILL_DIR/scripts/polymarket-scanner.mjs"
echo ""
echo "⏰ 设置 cron（可选）:"
echo '   在 agent 中执行: cron add --schedule "0 8 * * *" --tz Asia/Shanghai --message "每日新闻简报时间到了。请执行 daily-news skill。"'
