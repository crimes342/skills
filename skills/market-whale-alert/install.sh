#!/bin/bash
# market-whale-alert skill 安装脚本
# 用法：bash install.sh [目标workspace路径]
#
# 示例：
#   bash install.sh                              # 安装到 ~/.openclaw/workspace
#   bash install.sh /path/to/other/workspace     # 安装到指定 workspace

set -e

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
SKILL_DIR="$WORKSPACE/skills/market-whale-alert"

echo "🐋 安装 market-whale-alert skill → $SKILL_DIR"

mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/templates"

# ── 写入 SKILL.md ──
cat > "$SKILL_DIR/SKILL.md" << 'SKILL_EOF'
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
├── commodity-scanner.mjs   # 大宗商品 + 股指 + 国债 + 外汇
├── daily-summary.mjs       # 上一日异常总结生成
└── scheduler.mjs           # 智能调度器（判断推送频率）
```

## 执行模式

### 模式一：手动触发（用户请求）

用户说「巨鲸监控」→ 运行扫描器 → 生成报告 → 推送

```bash
node <SKILL_DIR>/scripts/polymarket-whale.mjs --json /tmp/polymarket-whale.json
node <SKILL_DIR>/scripts/crypto-whale.mjs --json /tmp/crypto-whale.json
node <SKILL_DIR>/scripts/futures-alert.mjs --json /tmp/futures-whale.json
node <SKILL_DIR>/scripts/commodity-scanner.mjs --json /tmp/commodity-whale.json
```

Agent 读取 JSON 文件，汇总生成人类可读报告。

### 模式二：每日晨报（上一日总结）

```bash
node <SKILL_DIR>/scripts/daily-summary.mjs --date yesterday --json /tmp/daily-summary.json
```

### 模式三：智能定时监控（核心功能）

```bash
node <SKILL_DIR>/scripts/scheduler.mjs
```

调度器输出建议的下次执行时间和推送级别。

#### 智能频率规则

| 条件 | 推送间隔 | 推送级别 |
|------|---------|---------|
| 任意市场 ≤ 1h 内到期/交割 | **5 分钟** | 🚨 Critical |
| 任意市场 ≤ 6h 内到期 + 成交量 > $10M | **15 分钟** | ⚠️ High |
| 任意市场 ≤ 24h 内到期 + 成交量 > $1M | **30 分钟** | 📌 Normal |
| 交易时段（主要市场开盘） | **1 小时** | 📊 Routine |
| 非交易时段 + 无紧急信号 | **4 小时** | 💤 Low |

## 数据源一览

| 模块 | API | 需要密钥 | 限流 |
|------|-----|---------|------|
| Polymarket | gamma-api.polymarket.com | ❌ | 宽松 |
| BTC链上 | blockchain.info | ❌ | 中等 |
| ETH链上 | api.etherscan.io | ❌ (免费tier) | 5次/s |
| 市场行情 | api.coingecko.com | ❌ | 10次/min |
| 期货数据 | fapi.binance.com | ❌ | 1200次/min |
| 期权数据 | deribit.com/api/v2 | ❌ | 宽松 |
| 大宗商品 | query1.finance.yahoo.com | ❌ | 宽松 |

## Cron 用法

```json
{
  "kind": "agentTurn",
  "message": "执行巨鲸异动扫描。读取调度建议并按频率执行。如无异常则回复 HEARTBEAT_OK。",
  "timeoutSeconds": 180
}
```

## Agent 集成指南

本技能不依赖任何特定工具。Agent 需要具备：

1. **执行脚本能力**：运行 Node.js 脚本
2. **读取文件能力**：读取 JSON 输出
3. **定时任务能力**：设置 cron 或类似调度
4. **消息推送能力**：将报告推送给用户（可选）
SKILL_EOF

# ── 写入 polymarket-whale.mjs ──
cat > "$SKILL_DIR/scripts/polymarket-whale.mjs" << 'POLY_EOF'
#!/usr/bin/env node
/**
 * Polymarket Whale Scanner 🐋
 * 监控临近到期巨额下注、价格极端变动、流动性异常
 * 零外部依赖，Node.js >= 18
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json:   { type: 'string', default: '/tmp/polymarket-whale.json' },
    hours:  { type: 'string', default: '24' },
    minVol: { type: 'string', default: '1000000' },
    maxRatio: { type: 'string', default: '20' },
  },
  strict: false,
});

const GAMMA_API = 'https://gamma-api.polymarket.com';
const CONFIG = {
  hoursUntilExpiry: Number(args.hours),
  minVolume: Number(args.minVol),
  anomalyRatio: Number(args.maxRatio),
  jsonOutput: args.json,
};

async function fetchJSON(url) {
  const resp = await fetch(url, { headers: { 'Accept': 'application/json' } });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${url}`);
  return resp.json();
}

function hoursUntil(d) { return (new Date(d).getTime() - Date.now()) / 3600000; }
function fmtPct(p) { return (parseFloat(p) * 100).toFixed(1) + '%'; }
function fmtMoney(n) {
  n = Number(n);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

async function getExpiringEvents() {
  const now = new Date().toISOString();
  const cutoff = new Date(Date.now() + CONFIG.hoursUntilExpiry * 3600000).toISOString();
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '100',
    order: 'end_date_min', ascending: 'true',
    end_date_min: now, end_date_max: cutoff,
  }));
}

async function getTrendingEvents() {
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '50',
    order: 'volume', ascending: 'false',
  }));
}

async function getNewHighVolumeEvents() {
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '50',
    order: 'volume_num', ascending: 'false',
  }));
}

function analyzeEvent(event, category) {
  const vol = Number(event.volume || 0);
  const liq = Number(event.liquidity || 0);
  const hrs = hoursUntil(event.endDate);
  const signals = [];
  const markets = event.markets || [];

  for (const m of markets) {
    const prices = JSON.parse(m.outcomePrices || '[]');
    const outcomes = JSON.parse(m.outcomes || '[]');
    for (let i = 0; i < prices.length; i++) {
      const p = parseFloat(prices[i]);
      if (p >= 0.95) signals.push({ type: 'PRICE_EXTREME', severity: 'high', detail: `${outcomes[i]}=${fmtPct(prices[i])} (几乎确定)` });
      else if (p <= 0.05 && p > 0) signals.push({ type: 'PRICE_EXTREME_LOW', severity: 'medium', detail: `${outcomes[i]}=${fmtPct(prices[i])} (几乎归零)` });
    }
  }

  if (liq > 0 && vol / liq > CONFIG.anomalyRatio) {
    signals.push({ type: 'VOLUME_SPIKE', severity: 'high', detail: `量/流动性=${(vol / liq).toFixed(1)}x` });
  }

  if (hrs < 24 && vol > CONFIG.minVolume) {
    signals.push({ type: 'HIGH_VOL_NEAR_EXPIRY', severity: 'critical', detail: `${hrs.toFixed(0)}h内到期 ${fmtMoney(vol)}` });
  }

  if (vol > 10e6) {
    signals.push({ type: 'MEGA_VOLUME', severity: 'high', detail: `成交量 ${fmtMoney(vol)}` });
  }

  let leading = { outcome: '?', price: 0 };
  for (const m of markets) {
    const p = JSON.parse(m.outcomePrices || '[]');
    const o = JSON.parse(m.outcomes || '[]');
    for (let i = 0; i < p.length; i++) {
      if (parseFloat(p[i]) > leading.price) leading = { outcome: o[i], price: parseFloat(p[i]) };
    }
  }

  return {
    title: event.title, slug: event.slug,
    url: `https://polymarket.com/event/${event.slug}`,
    endDate: event.endDate, hoursLeft: hrs,
    volume: vol, liquidity: liq, volumeLiquidityRatio: liq > 0 ? vol / liq : 0,
    leading, markets: markets.map(m => ({
      question: m.question, outcomes: JSON.parse(m.outcomes || '[]'), prices: JSON.parse(m.outcomePrices || '[]'),
    })),
    signals, signalCount: signals.length, category,
  };
}

function formatReport(results) {
  const lines = [];
  for (const r of results) {
    const severityEmoji = r.signals.some(s => s.severity === 'critical') ? '🚨' : r.signals.some(s => s.severity === 'high') ? '⚠️' : '📌';
    lines.push(`${severityEmoji} ${r.title}`);
    lines.push(`   到期: ${new Date(r.endDate).toISOString().replace('T', ' ').slice(0, 16)} UTC (${r.hoursLeft.toFixed(1)}h)`);
    lines.push(`   成交量: ${fmtMoney(r.volume)} | 流动性: ${fmtMoney(r.liquidity)} | 比率: ${r.volumeLiquidityRatio.toFixed(1)}x`);
    for (const m of r.markets) {
      lines.push(`   赔率: ${m.outcomes.map((o, i) => `${o}:${fmtPct(m.prices[i])}`).join(' | ')}`);
    }
    lines.push(`   领先: ${r.leading.outcome} (${fmtPct(String(r.leading.price))})`);
    if (r.signals.length) lines.push(`   🚨 信号: ${r.signals.map(s => s.detail).join('; ')}`);
    lines.push(`   🔗 ${r.url}`);
    lines.push('');
  }
  return lines.join('\n');
}

async function main() {
  console.error(`🐋 Polymarket Whale Scanner | ${new Date().toISOString()}`);
  const [expiring, trending, newHighVol] = await Promise.all([
    getExpiringEvents(), getTrendingEvents(), getNewHighVolumeEvents(),
  ]);

  const expiringAnalyzed = expiring.map(e => analyzeEvent(e, 'expiring'));
  const trendingAnalyzed = trending.map(e => analyzeEvent(e, 'trending'));
  const newHighVolAnalyzed = newHighVol.map(e => analyzeEvent(e, 'new_high_volume'));

  const expiringWhales = expiringAnalyzed.filter(r => r.signalCount > 0);
  const trendingWhales = trendingAnalyzed.filter(r => r.signalCount > 0);
  const newWhales = newHighVolAnalyzed.filter(r => r.signalCount > 0);

  const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
  const sortBySeverity = (a, b) => {
    const aMin = Math.min(...a.signals.map(s => severityOrder[s.severity] ?? 3));
    const bMin = Math.min(...b.signals.map(s => severityOrder[s.severity] ?? 3));
    return aMin - bMin || b.volume - a.volume;
  };

  expiringWhales.sort(sortBySeverity);
  trendingWhales.sort(sortBySeverity);
  newWhales.sort(sortBySeverity);

  console.log(`📊 临近到期: ${expiring.length} | 热门: ${trending.length} | 新高量: ${newHighVol.length}`);
  console.log(`🐋 鲸鱼信号: 临近到期 ${expiringWhales.length} | 热门 ${trendingWhales.length} | 新高量 ${newWhales.length}\n`);

  if (expiringWhales.length) {
    console.log('='.repeat(60) + '\n🚨 临近到期 + 巨额异动\n' + '='.repeat(60));
    console.log(formatReport(expiringWhales));
  }
  if (trendingWhales.length) {
    console.log('='.repeat(60) + '\n🔥 热门市场巨鲸动向\n' + '='.repeat(60));
    console.log(formatReport(trendingWhales.slice(0, 15)));
  }
  if (newWhales.length) {
    console.log('='.repeat(60) + '\n📈 成交量突增市场\n' + '='.repeat(60));
    console.log(formatReport(newWhales.slice(0, 10)));
  }

  const output = {
    scanTime: new Date().toISOString(),
    config: CONFIG,
    summary: {
      expiringTotal: expiring.length, trendingTotal: trending.length,
      newHighVolTotal: newHighVol.length,
      whaleSignals: expiringWhales.length + trendingWhales.length + newWhales.length,
    },
    items: [...expiringWhales, ...trendingWhales, ...newWhales],
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
POLY_EOF

# ── 写入 crypto-whale.mjs ──
cat > "$SKILL_DIR/scripts/crypto-whale.mjs" << 'CRYPTO_EOF'
#!/usr/bin/env node
/**
 * Crypto Whale Scanner 🐋₿
 * 监控 BTC/ETH 大额转账、交易所资金流、期货爆仓
 * 全部使用公开 API，无需密钥
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json:       { type: 'string', default: '/tmp/crypto-whale.json' },
    btcMin:     { type: 'string', default: '100' },
    ethMin:     { type: 'string', default: '1000' },
    stableMin:  { type: 'string', default: '1000000' },
    liqMin:     { type: 'string', default: '10000000' },
  },
  strict: false,
});

const CONFIG = {
  btcThreshold: Number(args.btcMin),
  ethThreshold: Number(args.ethMin),
  stableThreshold: Number(args.stableMin),
  liquidationThreshold: Number(args.liqMin),
  jsonOutput: args.json,
};

async function fetchJSON(url, timeout = 15000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: { 'Accept': 'application/json', 'User-Agent': 'MarketWhaleAlert/1.0' },
    });
    clearTimeout(timer);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
  } catch (e) { clearTimeout(timer); throw e; }
}

function fmtMoney(n) {
  n = Number(n);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}
function fmtBTC(n) { return `${Number(n).toFixed(2)} BTC`; }

async function scanBTCTransactions() {
  const alerts = [];
  try {
    const data = await fetchJSON('https://blockchain.info/unconfirmed-transactions?format=json');
    for (const tx of (data.txs || [])) {
      const totalOut = tx.out.reduce((sum, o) => sum + (o.value || 0), 0) / 1e8;
      if (totalOut >= CONFIG.btcThreshold) {
        const outputs = (tx.out || []).map(o => ({ addr: o.addr || 'unknown', value: o.value / 1e8 })).slice(0, 3);
        alerts.push({
          chain: 'BTC', type: 'LARGE_TRANSFER',
          severity: totalOut >= 1000 ? 'critical' : totalOut >= 500 ? 'high' : 'medium',
          amount: totalOut, amountStr: fmtBTC(totalOut), txHash: tx.hash,
          topOutputs: outputs,
          time: new Date((tx.time || Date.now() / 1000) * 1000).toISOString(),
        });
      }
    }
  } catch (e) { console.error(`⚠️ BTC 扫描失败: ${e.message}`); }
  return alerts;
}

async function scanETHTransactions() {
  const alerts = [];
  try {
    const blockData = await fetchJSON('https://api.etherscan.io/api?module=proxy&action=eth_blockNumber');
    const blockNum = parseInt(blockData.result, 16);
    for (let i = 0; i < 3; i++) {
      const block = await fetchJSON(`https://api.etherscan.io/api?module=proxy&action=eth_getBlockByNumber&tag=0x${(blockNum - i).toString(16)}&boolean=true`);
      for (const tx of (block.result?.transactions || [])) {
        const valueETH = parseInt(tx.value || '0x0', 16) / 1e18;
        if (valueETH >= CONFIG.ethThreshold) {
          alerts.push({
            chain: 'ETH', type: 'LARGE_TRANSFER',
            severity: valueETH >= 10000 ? 'critical' : valueETH >= 5000 ? 'high' : 'medium',
            amount: valueETH, amountStr: `${valueETH.toFixed(2)} ETH`,
            txHash: tx.hash, from: tx.from, to: tx.to,
            time: new Date().toISOString(),
          });
        }
      }
    }
  } catch (e) { console.error(`⚠️ ETH 扫描失败: ${e.message}`); }
  return alerts;
}

async function scanMarketData() {
  const alerts = [];
  try {
    const data = await fetchJSON('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=volume_desc&per_page=20&page=1&sparkline=false&price_change_percentage=1h,24h');
    for (const coin of data) {
      const change24h = coin.price_change_percentage_24h || 0;
      const change1h = coin.price_change_percentage_1h_in_currency || 0;
      const vol = coin.total_volume || 0;
      if (Math.abs(change24h) > 10 || Math.abs(change1h) > 5) {
        alerts.push({
          chain: coin.symbol.toUpperCase(), type: Math.abs(change1h) > 5 ? 'PRICE_FLASH' : 'PRICE_MOVE',
          severity: Math.abs(change24h) > 20 || Math.abs(change1h) > 8 ? 'critical' : 'high',
          price: coin.current_price, change24h: change24h.toFixed(2) + '%', change1h: change1h.toFixed(2) + '%',
          volume24h: vol, volumeStr: fmtMoney(vol),
          time: new Date().toISOString(),
        });
      }
      if (coin.market_cap > 0 && vol / coin.market_cap > 0.5) {
        alerts.push({
          chain: coin.symbol.toUpperCase(), type: 'VOLUME_ANOMALY', severity: 'high',
          price: coin.current_price, volume24h: vol, volumeStr: fmtMoney(vol),
          volumeMcapRatio: (vol / coin.market_cap * 100).toFixed(1) + '%',
          time: new Date().toISOString(),
        });
      }
    }
  } catch (e) { console.error(`⚠️ 市场行情扫描失败: ${e.message}`); }
  return alerts;
}

async function scanFuturesLiquidations() {
  const alerts = [];
  try {
    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');
    for (const t of tickers) {
      const sym = t.symbol || 'UNKNOWN';
      const vol = parseFloat(t.quoteVolume || 0);
      const priceChange = parseFloat(t.priceChangePercent || 0);
      const lastPrice = parseFloat(t.lastPrice || 0);
      if (Math.abs(priceChange) > 8 && vol > 10e6) {
        alerts.push({
          symbol: sym, type: 'FUTURES_VOLATILITY',
          severity: Math.abs(priceChange) > 15 ? 'critical' : 'high',
          price: lastPrice, change: priceChange.toFixed(2) + '%',
          volume24h: vol, volumeStr: fmtMoney(vol),
          time: new Date().toISOString(),
        });
      }
    }
    try {
      const openInterest = await fetchJSON('https://fapi.binance.com/fapi/v1/openInterest?symbol=BTCUSDT');
      alerts.push({
        symbol: 'BTCUSDT', type: 'OPEN_INTEREST', severity: 'info',
        openInterest: parseFloat(openInterest.openInterest),
        openInterestStr: fmtBTC(openInterest.openInterest),
        time: new Date().toISOString(),
      });
    } catch (e) { /* skip */ }

    const fundingRates = await fetchJSON('https://fapi.binance.com/fapi/v1/premiumIndex');
    for (const fr of fundingRates) {
      const rate = parseFloat(fr.lastFundingRate || 0);
      if (Math.abs(rate) > 0.001) {
        alerts.push({
          symbol: fr.symbol || 'UNKNOWN', type: 'FUNDING_RATE_ANOMALY',
          severity: Math.abs(rate) > 0.003 ? 'critical' : 'high',
          fundingRate: (rate * 100).toFixed(4) + '%',
          markPrice: parseFloat(fr.markPrice),
          nextFundingTime: new Date(fr.nextFundingTime).toISOString(),
          time: new Date().toISOString(),
        });
      }
    }
  } catch (e) { console.error(`⚠️ 期货扫描失败: ${e.message}`); }
  return alerts;
}

async function scanStablecoinTransfers() {
  const alerts = [];
  const stablecoins = [
    { name: 'USDT', contract: '0xdac17f958d2ee523a2206206994597c13d831ec7', decimals: 6 },
    { name: 'USDC', contract: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', decimals: 6 },
  ];
  for (const coin of stablecoins) {
    try {
      const data = await fetchJSON(
        `https://api.etherscan.io/api?module=account&action=tokentx&contractaddress=${coin.contract}&page=1&offset=20&sort=desc`
      );
      for (const tx of (data.result || [])) {
        const value = parseInt(tx.value || '0') / Math.pow(10, coin.decimals);
        if (value >= 1000000) {
          alerts.push({
            chain: coin.name, type: 'STABLECOIN_WHALE',
            severity: value >= 10e6 ? 'critical' : value >= 5e6 ? 'high' : 'medium',
            amount: value, amountStr: `${(value / 1e6).toFixed(2)}M ${coin.name}`,
            from: tx.from, to: tx.to, txHash: tx.hash,
            time: new Date(parseInt(tx.timeStamp) * 1000).toISOString(),
          });
        }
      }
    } catch (e) { console.error(`⚠️ ${coin.name} 扫描失败: ${e.message}`); }
  }
  return alerts;
}

function formatReport(alerts) {
  if (!alerts.length) return '   无重大异动\n';
  const lines = [];
  for (const a of alerts) {
    const emoji = a.severity === 'critical' ? '🚨' : a.severity === 'high' ? '⚠️' : '📌';
    const parts = [`${emoji} [${a.chain}] ${a.type}`];
    if (a.amountStr) parts.push(a.amountStr);
    if (a.price) parts.push(`价格: $${a.price}`);
    if (a.change24h) parts.push(`24h: ${a.change24h}`);
    if (a.change1h) parts.push(`1h: ${a.change1h}`);
    if (a.volumeStr) parts.push(`量: ${a.volumeStr}`);
    if (a.fundingRate) parts.push(`费率: ${a.fundingRate}`);
    if (a.txHash) parts.push(`tx: ${a.txHash.slice(0, 16)}...`);
    lines.push(`   ${parts.join(' | ')}`);
    if (a.topOutputs?.length) {
      lines.push(`      → ${a.topOutputs.map(o => `${o.addr.slice(0, 10)}... (${o.value.toFixed(2)} BTC)`).join(', ')}`);
    }
    if (a.from && a.to) {
      lines.push(`      ${a.from?.slice(0, 12)}... → ${a.to?.slice(0, 12)}...`);
    }
  }
  return lines.join('\n') + '\n';
}

async function main() {
  console.error(`🐋 Crypto Whale Scanner | ${new Date().toISOString()}`);
  const [btcAlerts, ethAlerts, marketAlerts, futuresAlerts, stableAlerts] = await Promise.all([
    scanBTCTransactions(), scanETHTransactions(), scanMarketData(),
    scanFuturesLiquidations(), scanStablecoinTransfers(),
  ]);

  const allAlerts = [...btcAlerts, ...ethAlerts, ...marketAlerts, ...futuresAlerts, ...stableAlerts];
  const critical = allAlerts.filter(a => a.severity === 'critical');
  const high = allAlerts.filter(a => a.severity === 'high');

  console.log(`📊 扫描完成 | ${new Date().toISOString()}`);
  console.log(`   BTC 大额: ${btcAlerts.length} | ETH 大额: ${ethAlerts.length} | 行情异动: ${marketAlerts.length} | 期货异动: ${futuresAlerts.length} | 稳定币: ${stableAlerts.length}`);
  console.log(`   🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  if (btcAlerts.length) { console.log('₿ BTC 大额转账\n' + '─'.repeat(40)); console.log(formatReport(btcAlerts)); }
  if (ethAlerts.length) { console.log('Ξ ETH 大额转账\n' + '─'.repeat(40)); console.log(formatReport(ethAlerts)); }
  if (stableAlerts.length) { console.log('💵 稳定币巨鲸\n' + '─'.repeat(40)); console.log(formatReport(stableAlerts)); }
  if (marketAlerts.length) { console.log('📈 行情异动\n' + '─'.repeat(40)); console.log(formatReport(marketAlerts)); }
  if (futuresAlerts.length) { console.log('🔥 期货异动\n' + '─'.repeat(40)); console.log(formatReport(futuresAlerts)); }
  if (!allAlerts.length) { console.log('✅ 当前无重大异动，市场平静。'); }

  const output = {
    scanTime: new Date().toISOString(),
    summary: {
      btcAlerts: btcAlerts.length, ethAlerts: ethAlerts.length,
      marketAlerts: marketAlerts.length, futuresAlerts: futuresAlerts.length,
      stableAlerts: stableAlerts.length, criticalCount: critical.length, highCount: high.length,
    },
    items: allAlerts,
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
CRYPTO_EOF

# ── 写入 futures-alert.mjs ──
cat > "$SKILL_DIR/scripts/futures-alert.mjs" << 'FUTURES_EOF'
#!/usr/bin/env node
/**
 * Futures & Options Whale Scanner 📈🐋
 * 监控期货爆仓、资金费率异常、期权大额到期
 * 使用 Binance + Deribit 公开 API
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json:       { type: 'string', default: '/tmp/futures-whale.json' },
    liqMin:     { type: 'string', default: '10000000' },
    fundRateHi: { type: 'string', default: '0.001' },
    fundRateLo: { type: 'string', default: '-0.0005' },
    oiChangePct:{ type: 'string', default: '10' },
  },
  strict: false,
});

const CONFIG = {
  liquidationThreshold: Number(args.liqMin),
  fundingRateHigh: Number(args.fundRateHi),
  fundingRateLow: Number(args.fundRateLo),
  oiChangeThreshold: Number(args.oiChangePct),
  jsonOutput: args.json,
};

async function fetchJSON(url, timeout = 15000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const resp = await fetch(url, { signal: controller.signal, headers: { 'Accept': 'application/json' } });
    clearTimeout(timer);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
  } catch (e) { clearTimeout(timer); throw e; }
}

function fmtMoney(n) {
  n = Number(n);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

async function scanBinanceFutures() {
  const alerts = [];
  try {
    const fundingRates = await fetchJSON('https://fapi.binance.com/fapi/v1/premiumIndex');
    for (const fr of fundingRates) {
      const rate = parseFloat(fr.lastFundingRate || 0);
      const markPrice = parseFloat(fr.markPrice || 0);
      const sym = fr.symbol || 'UNKNOWN';
      if (rate > CONFIG.fundingRateHigh) {
        alerts.push({ exchange: 'Binance', symbol: sym, type: 'FUNDING_RATE_HIGH', severity: rate > 0.003 ? 'critical' : 'high',
          detail: `资金费率 ${(rate * 100).toFixed(4)}%（多头付费）`, markPrice, fundingRate: rate,
          nextFunding: new Date(fr.nextFundingTime).toISOString(), interpretation: '多头过热，空头在收割多头资金费' });
      } else if (rate < CONFIG.fundingRateLow) {
        alerts.push({ exchange: 'Binance', symbol: sym, type: 'FUNDING_RATE_LOW', severity: Math.abs(rate) > 0.002 ? 'critical' : 'high',
          detail: `资金费率 ${(rate * 100).toFixed(4)}%（空头付费）`, markPrice, fundingRate: rate,
          nextFunding: new Date(fr.nextFundingTime).toISOString(), interpretation: '空头过热，多头在收割空头资金费' });
      }
    }

    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');
    for (const t of tickers) {
      const sym = t.symbol || 'UNKNOWN';
      const priceChange = parseFloat(t.priceChangePercent || 0);
      const vol = parseFloat(t.quoteVolume || 0);
      const highPrice = parseFloat(t.highPrice || 0);
      const lowPrice = parseFloat(t.lowPrice || 0);
      const lastPrice = parseFloat(t.lastPrice || 0);
      const amplitude = highPrice > 0 ? ((highPrice - lowPrice) / lowPrice * 100) : 0;

      if (amplitude > 15 && vol > 50e6) {
        alerts.push({ exchange: 'Binance', symbol: sym, type: 'EXTREME_VOLATILITY', severity: amplitude > 30 ? 'critical' : 'high',
          detail: `振幅 ${amplitude.toFixed(1)}% | 24h变化 ${priceChange.toFixed(2)}%`,
          price: lastPrice, high24h: highPrice, low24h: lowPrice, volume24h: vol, volumeStr: fmtMoney(vol),
          interpretation: priceChange > 0 ? '多头主导暴涨' : '空头主导暴跌' });
      }
      if (['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'].includes(sym) && vol > 1e9) {
        alerts.push({ exchange: 'Binance', symbol: sym, type: 'MEGA_VOLUME', severity: vol > 10e9 ? 'critical' : 'high',
          detail: `24h成交量 ${fmtMoney(vol)}`, price: lastPrice, priceChange: priceChange.toFixed(2) + '%', volume24h: vol,
          interpretation: '巨量交易，可能有大资金进出' });
      }
    }

    for (const sym of ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT']) {
      try {
        const oi = await fetchJSON(`https://fapi.binance.com/fapi/v1/openInterest?symbol=${sym}`);
        alerts.push({ exchange: 'Binance', symbol: sym, type: 'OPEN_INTEREST', severity: 'info',
          detail: `持仓量 ${parseFloat(oi.openInterest).toFixed(2)} 张`, openInterest: parseFloat(oi.openInterest), time: new Date().toISOString() });
      } catch (e) { /* skip */ }
    }

    try {
      const topTraders = await fetchJSON('https://fapi.binance.com/futures/data/topLongShortPositionRatio?symbol=BTCUSDT&period=1h&limit=1');
      if (topTraders.length) {
        const latest = topTraders[0];
        const longRatio = parseFloat(latest.longAccount || 0);
        const shortRatio = parseFloat(latest.shortAccount || 0);
        alerts.push({ exchange: 'Binance', symbol: 'BTCUSDT', type: 'TOP_TRADER_RATIO', severity: 'info',
          detail: `大户多空比 ${longRatio.toFixed(2)} : ${shortRatio.toFixed(2)}`,
          longRatio, shortRatio, time: new Date(latest.timestamp).toISOString(),
          interpretation: longRatio > 0.6 ? '大户偏多' : shortRatio > 0.6 ? '大户偏空' : '多空均衡' });
      }
    } catch (e) { /* skip */ }
  } catch (e) { console.error(`⚠️ Binance Futures 扫描失败: ${e.message}`); }
  return alerts;
}

async function scanDeribitOptions() {
  const alerts = [];
  try {
    for (const currency of ['BTC', 'ETH']) {
      const expiriesResp = await fetchJSON(`https://www.deribit.com/api/v2/public/get_expirations?currency=${currency}&kind=option`);
      const expiryDates = expiriesResp.result?.[currency.toLowerCase()]?.option || [];
      if (!Array.isArray(expiryDates) || expiryDates.length === 0) continue;

      for (const expiry of expiryDates.slice(0, 3)) {
        try {
          const bookSummary = await fetchJSON(`https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=${currency}&kind=option&expiration=${expiry}`);
          const instruments = bookSummary.result || [];
          let totalOI = 0;
          for (const inst of instruments) { totalOI += inst.open_interest || 0; }
          const avgPrice = instruments[0]?.underlying_price || 0;
          const totalNotional = totalOI * avgPrice;
          if (totalNotional > 100e6) {
            alerts.push({ exchange: 'Deribit', symbol: `${currency}期权`, type: 'OPTIONS_EXPIRY',
              severity: totalNotional > 1e9 ? 'critical' : 'high',
              detail: `${expiry} 到期 | 名义价值 ${fmtMoney(totalNotional)} | OI ${totalOI.toFixed(0)} 张`,
              expiry, totalOI, totalNotional, interpretation: '大额期权到期，可能引发标的资产波动' });
          }
        } catch (e) { /* skip */ }
      }

      try {
        const lastTrade = await fetchJSON(`https://www.deribit.com/api/v2/public/get_last_trades_by_currency?currency=${currency}&kind=option&count=50&sorting=desc`);
        for (const trade of (lastTrade.result?.trades || [])) {
          const amount = trade.amount || 0;
          const indexPrice = trade.index_price || 0;
          const notional = amount * indexPrice;
          if (notional > 1e6) {
            alerts.push({ exchange: 'Deribit', symbol: trade.instrument_name, type: 'OPTIONS_LARGE_TRADE',
              severity: notional > 50e6 ? 'critical' : notional > 10e6 ? 'high' : 'medium',
              detail: `${trade.direction?.toUpperCase()} ${amount} ${currency} @ $${trade.price} | 名义 ${fmtMoney(notional)}`,
              amount, price: trade.price, notional, direction: trade.direction,
              time: new Date(trade.timestamp).toISOString() });
          }
        }
      } catch (e) { /* skip */ }
    }
  } catch (e) { console.error(`⚠️ Deribit 扫描失败: ${e.message}`); }
  return alerts;
}

async function estimateLiquidations() {
  const alerts = [];
  try {
    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');
    for (const t of tickers) {
      const priceChange = Math.abs(parseFloat(t.priceChangePercent || 0));
      const vol = parseFloat(t.quoteVolume || 0);
      if (priceChange > 10 && vol > 100e6) {
        const estimatedLiquidation = vol * (priceChange / 100) * 0.15;
        alerts.push({
          symbol: t.symbol || 'UNKNOWN', type: 'ESTIMATED_LIQUIDATIONS',
          severity: estimatedLiquidation > 100e6 ? 'critical' : estimatedLiquidation > 50e6 ? 'high' : 'medium',
          priceChange: t.priceChangePercent + '%', volume24h: vol, volumeStr: fmtMoney(vol),
          estimatedLiquidation, estimatedStr: fmtMoney(estimatedLiquidation),
          interpretation: parseFloat(t.priceChangePercent) > 0 ? '空头被爆' : '多头被爆',
          time: new Date().toISOString() });
      }
    }
  } catch (e) { console.error(`⚠️ 清算估算失败: ${e.message}`); }
  return alerts;
}

function formatSection(title, alerts) {
  if (!alerts.length) return '';
  const lines = [title, '─'.repeat(40)];
  for (const a of alerts) {
    const emoji = a.severity === 'critical' ? '🚨' : a.severity === 'high' ? '⚠️' : a.severity === 'info' ? '📊' : '📌';
    lines.push(`   ${emoji} [${a.exchange || ''}] ${a.symbol} | ${a.type}`);
    lines.push(`      ${a.detail}`);
    if (a.interpretation) lines.push(`      💡 ${a.interpretation}`);
    if (a.time) lines.push(`      🕐 ${a.time}`);
    lines.push('');
  }
  return lines.join('\n') + '\n';
}

async function main() {
  console.error(`📈 Futures & Options Whale Scanner | ${new Date().toISOString()}`);
  const [binanceAlerts, deribitAlerts, liquidationAlerts] = await Promise.all([
    scanBinanceFutures(), scanDeribitOptions(), estimateLiquidations(),
  ]);

  const allAlerts = [...binanceAlerts, ...deribitAlerts, ...liquidationAlerts];
  const critical = allAlerts.filter(a => a.severity === 'critical');
  const high = allAlerts.filter(a => a.severity === 'high');

  console.log(`📊 扫描完成 | Binance: ${binanceAlerts.length} | Deribit: ${deribitAlerts.length} | 清算估算: ${liquidationAlerts.length}`);
  console.log(`   🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  const sections = [
    formatSection('💰 资金费率异常', allAlerts.filter(a => a.type.startsWith('FUNDING'))),
    formatSection('🔥 极端波动', allAlerts.filter(a => a.type === 'EXTREME_VOLATILITY')),
    formatSection('🐋 大额成交量', allAlerts.filter(a => a.type === 'MEGA_VOLUME')),
    formatSection('💥 预估爆仓', allAlerts.filter(a => a.type === 'ESTIMATED_LIQUIDATIONS')),
    formatSection('📊 期权大额到期/交易', allAlerts.filter(a => a.type.startsWith('OPTIONS'))),
    formatSection('📈 持仓量数据', allAlerts.filter(a => a.type === 'OPEN_INTEREST')),
    formatSection('🏦 大户多空比', allAlerts.filter(a => a.type === 'TOP_TRADER_RATIO')),
  ].filter(Boolean);

  if (sections.length) { for (const s of sections) console.log(s); }
  else { console.log('✅ 当前无重大衍生品异动，市场平稳。'); }

  writeFileSync(CONFIG.jsonOutput, JSON.stringify({
    scanTime: new Date().toISOString(),
    summary: { binanceAlerts: binanceAlerts.length, deribitAlerts: deribitAlerts.length,
      liquidationAlerts: liquidationAlerts.length, criticalCount: critical.length, highCount: high.length },
    items: allAlerts,
  }, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
FUTURES_EOF

# ── 写入 commodity-scanner.mjs ──
cat > "$SKILL_DIR/scripts/commodity-scanner.mjs" << 'COMMODITY_EOF'
#!/usr/bin/env node
/**
 * Commodity & Traditional Futures Scanner 🛢️🥇
 * 监控大宗商品期货期权异动
 * 数据源：Yahoo Finance（公开，无需密钥）
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: { json: { type: 'string', default: '/tmp/commodity-whale.json' } },
  strict: false,
});

const CONFIG = { jsonOutput: args.json, priceChangeWarn: 2, priceChangeCrit: 5, volumeAnomalyRatio: 2 };

const COMMODITIES = [
  { symbol: 'GC=F',  name: '黄金期货',    category: '贵金属', unit: '$/oz' },
  { symbol: 'SI=F',  name: '白银期货',    category: '贵金属', unit: '$/oz' },
  { symbol: 'PL=F',  name: '铂金期货',    category: '贵金属', unit: '$/oz' },
  { symbol: 'CL=F',  name: 'WTI原油期货', category: '能源', unit: '$/桶' },
  { symbol: 'BZ=F',  name: '布伦特原油',  category: '能源', unit: '$/桶' },
  { symbol: 'NG=F',  name: '天然气期货',  category: '能源', unit: '$/MMBtu' },
  { symbol: 'HG=F',  name: '铜期货',      category: '工业金属', unit: '$/lb' },
  { symbol: 'ZC=F',  name: '玉米期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'ZS=F',  name: '大豆期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'ZW=F',  name: '小麦期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'CT=F',  name: '棉花期货',    category: '农产品', unit: '$/lb' },
  { symbol: 'KC=F',  name: '咖啡期货',    category: '农产品', unit: '$/lb' },
  { symbol: 'SB=F',  name: '糖期货',      category: '农产品', unit: '$/lb' },
  { symbol: 'ES=F',  name: '标普500期货', category: '股指', unit: '点' },
  { symbol: 'NQ=F',  name: '纳斯达克期货',category: '股指', unit: '点' },
  { symbol: 'YM=F',  name: '道琼斯期货',  category: '股指', unit: '点' },
  { symbol: 'NKD=F', name: '日经225期货', category: '股指', unit: '点' },
  { symbol: 'ZB=F',  name: '美国国债期货',category: '国债', unit: '点' },
  { symbol: 'ZN=F',  name: '10年期国债',  category: '国债', unit: '点' },
  { symbol: 'DX=F',  name: '美元指数期货',category: '外汇', unit: '点' },
  { symbol: '6E=F',  name: '欧元期货',    category: '外汇', unit: '' },
  { symbol: '6J=F',  name: '日元期货',    category: '外汇', unit: '' },
];

async function fetchYahooQuote(symbol) {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=5d`;
    const resp = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: AbortSignal.timeout(10000) });
    if (!resp.ok) return null;
    const data = await resp.json();
    const result = data.chart?.result?.[0];
    if (!result) return null;
    const meta = result.meta;
    const quotes = result.indicators?.quote?.[0];
    const currentPrice = meta.regularMarketPrice || 0;
    const prevClose = meta.chartPreviousClose || meta.previousClose || 0;
    const change = prevClose ? ((currentPrice - prevClose) / prevClose * 100) : 0;
    const volumes = (quotes?.volume || []).filter(v => v > 0);
    const avgVolume = volumes.length > 1 ? volumes.slice(0, -1).reduce((a, b) => a + b, 0) / (volumes.length - 1) : 0;
    const latestVolume = volumes[volumes.length - 1] || 0;
    const highs = (quotes?.high || []).filter(v => v > 0);
    const lows = (quotes?.low || []).filter(v => v > 0);
    const dayHigh = highs[highs.length - 1] || currentPrice;
    const dayLow = lows[lows.length - 1] || currentPrice;
    const amplitude = dayLow > 0 ? ((dayHigh - dayLow) / dayLow * 100) : 0;
    return { symbol, price: currentPrice, prevClose, change: change.toFixed(2) + '%', changeNum: change,
      dayHigh, dayLow, amplitude: amplitude.toFixed(2) + '%', amplitudeNum: amplitude,
      volume: latestVolume, avgVolume, volumeRatio: avgVolume > 0 ? (latestVolume / avgVolume).toFixed(2) : 'N/A',
      volumeRatioNum: avgVolume > 0 ? latestVolume / avgVolume : 0 };
  } catch (e) { console.error(`   ⚠️ ${symbol}: ${e.message}`); return null; }
}

function analyzeQuote(quote, commodity) {
  if (!quote) return null;
  const signals = [];
  const absChange = Math.abs(quote.changeNum);
  if (absChange >= CONFIG.priceChangeCrit) signals.push({ type: 'PRICE_MOVE', severity: 'critical', detail: `24h变化 ${quote.changeNum > 0 ? '+' : ''}${quote.change}%` });
  else if (absChange >= CONFIG.priceChangeWarn) signals.push({ type: 'PRICE_MOVE', severity: 'high', detail: `24h变化 ${quote.changeNum > 0 ? '+' : ''}${quote.change}%` });
  if (Math.abs(quote.amplitudeNum) >= 5) signals.push({ type: 'HIGH_AMPLITUDE', severity: 'high', detail: `日内振幅 ${quote.amplitude}%` });
  if (quote.volumeRatioNum >= CONFIG.volumeAnomalyRatio) signals.push({ type: 'VOLUME_SPIKE', severity: quote.volumeRatioNum >= 3 ? 'critical' : 'high', detail: `成交量 ${quote.volumeRatio}x 均值` });
  return { ...commodity, price: quote.price, change: quote.change, changeNum: quote.changeNum,
    amplitude: quote.amplitude, volume: quote.volume, avgVolume: quote.avgVolume, volumeRatio: quote.volumeRatio,
    signals, signalCount: signals.length,
    severity: signals.some(s => s.severity === 'critical') ? 'critical' : signals.some(s => s.severity === 'high') ? 'high' : 'normal' };
}

function formatReport(results) {
  const lines = [];
  const byCategory = {};
  for (const r of results) { if (!byCategory[r.category]) byCategory[r.category] = []; byCategory[r.category].push(r); }
  const catEmoji = { '贵金属': '🥇', '能源': '🛢️', '工业金属': '⚙️', '农产品': '🌾', '股指': '📊', '国债': '📜', '外汇': '💱' };
  for (const [cat, items] of Object.entries(byCategory)) {
    lines.push(`${catEmoji[cat] || '📌'} ${cat}`);
    lines.push('─'.repeat(40));
    for (const item of items) {
      const alertEmoji = item.severity === 'critical' ? '🚨' : item.severity === 'high' ? '⚠️' : '  ';
      const changeStr = item.changeNum >= 0 ? `+${item.change}` : item.change;
      const priceStr = item.price >= 1000 ? item.price.toFixed(0) : item.price >= 1 ? item.price.toFixed(2) : item.price.toFixed(4);
      lines.push(`${alertEmoji} ${item.name.padEnd(12)} ${priceStr} ${item.unit}  (${changeStr})`);
      if (item.signals.length) { for (const s of item.signals) lines.push(`      → ${s.detail}`); }
    }
    lines.push('');
  }
  return lines.join('\n');
}

async function main() {
  console.error(`🛢️ Commodity Scanner | ${new Date().toISOString()}`);
  const results = [];
  const batchSize = 5;
  for (let i = 0; i < COMMODITIES.length; i += batchSize) {
    const batch = COMMODITIES.slice(i, i + batchSize);
    const quotes = await Promise.all(batch.map(c => fetchYahooQuote(c.symbol)));
    for (let j = 0; j < batch.length; j++) { const analyzed = analyzeQuote(quotes[j], batch[j]); if (analyzed) results.push(analyzed); }
    if (i + batchSize < COMMODITIES.length) await new Promise(r => setTimeout(r, 500));
  }

  const critical = results.filter(r => r.severity === 'critical');
  const high = results.filter(r => r.severity === 'high');
  const withSignals = results.filter(r => r.signalCount > 0);

  console.log(`\n📊 扫描完成 | ${new Date().toISOString()}`);
  console.log(`   合约: ${results.length} | 🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  if (withSignals.length) {
    console.log('═'.repeat(50) + '\n🚨 大宗商品异动信号\n' + '═'.repeat(50) + '\n');
    for (const item of withSignals) {
      const emoji = item.severity === 'critical' ? '🚨' : '⚠️';
      console.log(`${emoji} ${item.name} (${item.symbol})`);
      console.log(`   价格: ${item.price} ${item.unit} | 变化: ${item.change} | 振幅: ${item.amplitude}`);
      console.log(`   成交量: ${item.volume} | 均值: ${item.avgVolume} | 比率: ${item.volumeRatio}x`);
      for (const s of item.signals) console.log(`   📌 ${s.type}: ${s.detail}`);
      console.log('');
    }
  }

  console.log('═'.repeat(50) + '\n📋 全部合约行情\n' + '═'.repeat(50) + '\n');
  console.log(formatReport(results));

  writeFileSync(CONFIG.jsonOutput, JSON.stringify({
    scanTime: new Date().toISOString(),
    summary: { total: results.length, critical: critical.length, high: high.length, withSignals: withSignals.length },
    alerts: withSignals.map(r => ({ symbol: r.symbol, name: r.name, category: r.category, price: r.price, change: r.change, amplitude: r.amplitude, volumeRatio: r.volumeRatio, signals: r.signals, severity: r.severity })),
    items: results.map(r => ({ symbol: r.symbol, name: r.name, category: r.category, price: r.price, change: r.change, amplitude: r.amplitude, volume: r.volume, avgVolume: r.avgVolume, volumeRatio: r.volumeRatio, signals: r.signals })),
  }, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
COMMODITY_EOF

# ── 写入 daily-summary.mjs ──
cat > "$SKILL_DIR/scripts/daily-summary.mjs" << 'DAILY_EOF'
#!/usr/bin/env node
/**
 * Daily Summary Generator 📋
 * 生成前一日市场异常检测总结
 */
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: { date: { type: 'string', default: 'yesterday' }, json: { type: 'string', default: '/tmp/daily-summary.json' }, dataDir: { type: 'string', default: '/tmp' } },
  strict: false,
});

function getDateRange(dateArg) {
  const now = new Date();
  let target;
  if (dateArg === 'yesterday') target = new Date(now.getTime() - 86400000);
  else if (dateArg === 'today') target = now;
  else target = new Date(dateArg);
  const yyyy = target.getFullYear();
  const mm = String(target.getMonth() + 1).padStart(2, '0');
  const dd = String(target.getDate()).padStart(2, '0');
  return { dateStr: `${yyyy}-${mm}-${dd}`, start: new Date(`${yyyy}-${mm}-${dd}T00:00:00Z`), end: new Date(`${yyyy}-${mm}-${dd}T23:59:59Z`) };
}

function loadJsonSafe(path) { try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; } }

function buildSummary(data, source) {
  const items = data.items || [];
  const critical = items.filter(i => i.severity === 'critical' || (i.signals && i.signals.some(s => s.severity === 'critical')));
  const high = items.filter(i => i.severity === 'high' || (i.signals && i.signals.some(s => s.severity === 'high')));
  return { source, totalItems: items.length, criticalCount: critical.length, highCount: high.length,
    criticalItems: critical.slice(0, 10).map(i => ({ title: i.title || i.symbol || i.instrument || 'Unknown', type: i.type || 'UNKNOWN', detail: i.detail || i.analysis || '', volume: i.volume || i.volume24h || i.notional || 0, url: i.url || '' })),
    highItems: high.slice(0, 10).map(i => ({ title: i.title || i.symbol || i.instrument || 'Unknown', type: i.type || 'UNKNOWN', detail: i.detail || i.analysis || '', volume: i.volume || i.volume24h || i.notional || 0, url: i.url || '' })) };
}

function formatMoney(n) { n = Number(n || 0); if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`; if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`; if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`; return `$${n.toFixed(0)}`; }

function generateTextReport(summaries, dateRange) {
  const lines = [`📋 市场异常日报 | ${dateRange.dateStr}`, '═'.repeat(50), ''];
  let totalCritical = 0, totalHigh = 0;
  for (const s of summaries) { totalCritical += s.criticalCount; totalHigh += s.highCount; }
  lines.push(`📊 统计总览\n   🚨 Critical: ${totalCritical}\n   ⚠️ High: ${totalHigh}\n`);

  const poly = summaries.find(s => s.source === 'polymarket');
  if (poly?.criticalItems.length) {
    lines.push('🎰 Polymarket 异常 Top 5\n' + '─'.repeat(40));
    for (const item of poly.criticalItems.slice(0, 5)) {
      lines.push(`   🚨 ${item.title}\n      成交量: ${formatMoney(item.volume)} | ${item.type}`);
      if (item.url) lines.push(`      🔗 ${item.url}`);
      lines.push('');
    }
  }

  const crypto = summaries.find(s => s.source === 'crypto');
  if (crypto && (crypto.criticalItems.length || crypto.highItems.length)) {
    lines.push('₿ 加密市场异动 Top 5\n' + '─'.repeat(40));
    for (const item of [...crypto.criticalItems, ...crypto.highItems].slice(0, 5)) {
      lines.push(`   ${crypto.criticalItems.includes(item) ? '🚨' : '⚠️'} ${item.title} | ${item.type}`);
      if (item.detail) lines.push(`      ${item.detail}`);
      lines.push('');
    }
  }

  const futures = summaries.find(s => s.source === 'futures');
  if (futures && (futures.criticalItems.length || futures.highItems.length)) {
    lines.push('📈 期货期权异动 Top 5\n' + '─'.repeat(40));
    for (const item of [...futures.criticalItems, ...futures.highItems].slice(0, 5)) {
      lines.push(`   ${futures.criticalItems.includes(item) ? '🚨' : '⚠️'} ${item.title} | ${item.type}`);
      if (item.detail) lines.push(`      ${item.detail}`);
      lines.push('');
    }
  }

  if (totalCritical === 0 && totalHigh === 0) lines.push('✅ 昨日无重大异常信号，市场整体平稳。');
  return lines.join('\n');
}

async function main() {
  const dateRange = getDateRange(args.date);
  console.error(`📋 Daily Summary | ${dateRange.dateStr}`);
  const sources = [
    { file: `${args.dataDir}/polymarket-whale.json`, name: 'polymarket' },
    { file: `${args.dataDir}/crypto-whale.json`, name: 'crypto' },
    { file: `${args.dataDir}/futures-whale.json`, name: 'futures' },
    { file: `${args.dataDir}/commodity-whale.json`, name: 'commodity' },
  ];
  const summaries = [];
  for (const src of sources) {
    const data = loadJsonSafe(src.file);
    if (data) { summaries.push(buildSummary(data, src.name)); console.error(`   ✅ 加载 ${src.name}: ${data.items?.length || 0} 条记录`); }
    else console.error(`   ⚠️ ${src.name}: 无数据文件`);
  }

  const textReport = generateTextReport(summaries, dateRange);
  console.log(textReport);

  writeFileSync(args.json, JSON.stringify({
    date: dateRange.dateStr, generatedAt: new Date().toISOString(), summaries,
    totalCritical: summaries.reduce((s, x) => s + x.criticalCount, 0),
    totalHigh: summaries.reduce((s, x) => s + x.highCount, 0),
  }, null, 2));
  console.error(`\n📁 JSON → ${args.json}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
DAILY_EOF

# ── 写入 scheduler.mjs ──
cat > "$SKILL_DIR/scripts/scheduler.mjs" << 'SCHEDULER_EOF'
#!/usr/bin/env node
/**
 * Smart Scheduler 🧠⏰
 * 智能调度器：根据市场状态和异常严重程度决定推送频率
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json: { type: 'string', default: '/tmp/market-whale-scheduler.json' },
    stateFile: { type: 'string', default: '/tmp/market-whale-state.json' },
    polyFile: { type: 'string', default: '/tmp/polymarket-whale.json' },
    cryptoFile: { type: 'string', default: '/tmp/crypto-whale.json' },
    futuresFile: { type: 'string', default: '/tmp/futures-whale.json' },
    commodityFile: { type: 'string', default: '/tmp/commodity-whale.json' },
  },
  strict: false,
});

const MARKET_HOURS = {
  US_STOCK: { open: '13:30', close: '20:00', label: '美股' },
  US_FUTURES: { open: '23:00', close: '22:00', label: '美国期货(近24h)' },
  EU_STOCK: { open: '08:00', close: '16:30', label: '欧股' },
  ASIA_STOCK: { open: '00:00', close: '08:00', label: '亚洲股市' },
  CRYPTO: { open: '00:00', close: '23:59', label: '加密货币(24/7)' },
  POLYMARKET: { open: '00:00', close: '23:59', label: 'Polymarket(24/7)' },
};

const INTERVALS = {
  CRITICAL: { minutes: 5, label: '5m', urgency: 'critical' },
  HIGH: { minutes: 15, label: '15m', urgency: 'high' },
  NORMAL: { minutes: 30, label: '30m', urgency: 'normal' },
  ROUTINE: { minutes: 60, label: '1h', urgency: 'routine' },
  LOW: { minutes: 240, label: '4h', urgency: 'low' },
};

function loadJsonSafe(path) { try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; } }
function loadState() { return loadJsonSafe(args.stateFile) || { lastRun: null, lastInterval: null, consecutiveCalm: 0 }; }
function saveState(state) { writeFileSync(args.stateFile, JSON.stringify(state, null, 2)); }

function isMarketOpen(marketKey) {
  const market = MARKET_HOURS[marketKey];
  if (!market) return false;
  if (market.open === '00:00' && market.close === '23:59') return true;
  const now = new Date();
  const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
  const [oH, oM] = market.open.split(':').map(Number);
  const [cH, cM] = market.close.split(':').map(Number);
  const openMin = oH * 60 + oM;
  const closeMin = cH * 60 + cM;
  return openMin < closeMin ? (nowMin >= openMin && nowMin <= closeMin) : (nowMin >= openMin || nowMin <= closeMin);
}

function getOpenMarkets() { return Object.entries(MARKET_HOURS).filter(([key]) => isMarketOpen(key)).map(([, m]) => m.label); }

function analyzeExpirations(polyData) {
  const reasons = []; let closestExpiry = Infinity;
  if (!polyData?.items) return { reasons, closestExpiry };
  for (const item of polyData.items) {
    const hrs = item.hoursLeft ?? ((new Date(item.endDate).getTime() - Date.now()) / 3600000);
    if (hrs < 0) continue;
    const vol = item.volume || 0;
    if (hrs <= 1) { closestExpiry = Math.min(closestExpiry, hrs); reasons.push(`${item.title} ${hrs.toFixed(1)}h内到期 (${(vol/1e6).toFixed(1)}M)`); }
    else if (hrs <= 6 && vol > 10e6) { closestExpiry = Math.min(closestExpiry, hrs); reasons.push(`${item.title} ${hrs.toFixed(1)}h内到期 (${(vol/1e6).toFixed(1)}M)`); }
    else if (hrs <= 24 && vol > 1e6) { closestExpiry = Math.min(closestExpiry, hrs); }
  }
  return { reasons, closestExpiry };
}

function analyzeSignals(data, label) {
  const reasons = [];
  if (!data?.items) return reasons;
  for (const item of data.items) {
    if (item.severity === 'critical') reasons.push(`${item.symbol || item.name || item.title || label} ${item.type || ''} (Critical)`);
  }
  return reasons;
}

function analyzeOptionExpiries(futuresData) {
  let closestExpiry = Infinity;
  if (!futuresData?.items) return closestExpiry;
  const months = { JAN:0,FEB:1,MAR:2,APR:3,MAY:4,JUN:5,JUL:6,AUG:7,SEP:8,OCT:9,NOV:10,DEC:11 };
  for (const item of futuresData.items) {
    if (item.type === 'OPTIONS_EXPIRY' && item.expiry) {
      const match = item.expiry.match(/(\d{2})(\w{3})(\d{2})/);
      if (match) {
        const expiryDate = new Date(Date.UTC(2000 + parseInt(match[3]), months[match[2]], parseInt(match[1]), 23, 59, 59));
        const hrs = (expiryDate.getTime() - Date.now()) / 3600000;
        if (hrs > 0 && hrs < closestExpiry) closestExpiry = hrs;
      }
    }
  }
  return closestExpiry;
}

function determineInterval(polyData, cryptoData, futuresData, commodityData, state) {
  const reasons = [];
  let interval = INTERVALS.LOW;
  let closestExpiry = Infinity;

  const polyAnalysis = analyzeExpirations(polyData);
  reasons.push(...polyAnalysis.reasons);
  closestExpiry = Math.min(closestExpiry, polyAnalysis.closestExpiry);
  reasons.push(...analyzeSignals(cryptoData, 'crypto'));
  reasons.push(...analyzeSignals(futuresData, 'futures'));
  reasons.push(...analyzeSignals(commodityData, 'commodity'));
  const optionExpiry = analyzeOptionExpiries(futuresData);
  closestExpiry = Math.min(closestExpiry, optionExpiry);

  if (closestExpiry <= 1 || reasons.length >= 5) interval = INTERVALS.CRITICAL;
  else if (closestExpiry <= 6 || reasons.length >= 3) interval = INTERVALS.HIGH;
  else if (closestExpiry <= 24 || reasons.length >= 1) interval = INTERVALS.NORMAL;
  else if (isMarketOpen('US_STOCK') || isMarketOpen('EU_STOCK')) interval = INTERVALS.ROUTINE;

  if (reasons.length === 0) { state.consecutiveCalm = (state.consecutiveCalm || 0) + 1; if (state.consecutiveCalm >= 3 && interval.minutes < INTERVALS.ROUTINE.minutes) interval = INTERVALS.ROUTINE; }
  else state.consecutiveCalm = 0;

  return { interval, reasons, closestExpiry };
}

function formatReport(schedule) {
  const urgencyEmoji = { critical: '🚨', high: '⚠️', normal: '📌', routine: '📊', low: '💤' };
  const lines = [`⏰ 调度建议 | ${schedule.currentTime}`, '─'.repeat(40),
    `${urgencyEmoji[schedule.urgency]} 级别: ${schedule.urgency.toUpperCase()}`,
    `⏱️ 下次扫描: ${schedule.nextRun}`, `🔄 间隔: ${schedule.interval}`, ''];
  if (schedule.closestExpiryHours) lines.push(`⏳ 最近到期: ${schedule.closestExpiryHours}h`);
  if (schedule.openMarkets.length) lines.push(`🏪 开盘市场: ${schedule.openMarkets.join(', ')}`);
  if (schedule.reasons.length) { lines.push('', `📋 触发原因 (${schedule.reasonCount}):`); for (const r of schedule.reasons) lines.push(`   • ${r}`); }
  else { lines.push('', '✅ 当前无异常信号'); }
  return lines.join('\n');
}

async function main() {
  const state = loadState();
  const polyData = loadJsonSafe(args.polyFile);
  const cryptoData = loadJsonSafe(args.cryptoFile);
  const futuresData = loadJsonSafe(args.futuresFile);
  const commodityData = loadJsonSafe(args.commodityFile);

  const openMarkets = getOpenMarkets();
  const { interval, reasons, closestExpiry } = determineInterval(polyData, cryptoData, futuresData, commodityData, state);
  const now = new Date();
  const schedule = {
    currentTime: now.toISOString(), nextRun: new Date(now.getTime() + interval.minutes * 60000).toISOString(),
    interval: interval.label, intervalMinutes: interval.minutes, urgency: interval.urgency,
    reasons: reasons.slice(0, 8), reasonCount: reasons.length,
    closestExpiryHours: closestExpiry === Infinity ? null : closestExpiry.toFixed(1),
    openMarkets, consecutiveCalm: 0,
  };

  state.lastRun = schedule.currentTime; state.lastInterval = schedule.interval;
  state.consecutiveCalm = reasons.length === 0 ? (state.consecutiveCalm || 0) + 1 : 0;
  saveState(state);

  console.log(formatReport(schedule));
  writeFileSync(args.json, JSON.stringify(schedule, null, 2));
  console.error(`\n📁 JSON → ${args.json}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
SCHEDULER_EOF

# ── 设置执行权限 ──
chmod +x "$SKILL_DIR/scripts/"*.mjs

echo ""
echo "✅ market-whale-alert skill 已安装到: $SKILL_DIR"
echo ""
echo "📁 文件:"
echo "   $SKILL_DIR/SKILL.md"
echo "   $SKILL_DIR/scripts/polymarket-whale.mjs"
echo "   $SKILL_DIR/scripts/crypto-whale.mjs"
echo "   $SKILL_DIR/scripts/futures-alert.mjs"
echo "   $SKILL_DIR/scripts/commodity-scanner.mjs"
echo "   $SKILL_DIR/scripts/daily-summary.mjs"
echo "   $SKILL_DIR/scripts/scheduler.mjs"
echo ""
echo "🧪 验证: node $SKILL_DIR/scripts/scheduler.mjs"
echo ""
echo "📊 覆盖市场:"
echo "   🎰 Polymarket 预测市场"
echo "   ₿  加密货币 (BTC/ETH/稳定币/期货/期权)"
echo "   🛢️ 大宗商品 (贵金属/能源/农产品)"
echo "   📊 股指期货 (标普/纳指/道指/日经)"
echo "   📜 国债期货 (美国国债/10年期)"
echo "   💱 外汇期货 (美元/欧元/日元)"
echo ""
echo "⏰ 设置 cron（可选）:"
echo '   在 agent 中执行: cron add --schedule "0 * * * *" --message "执行巨鲸异动扫描。"'
