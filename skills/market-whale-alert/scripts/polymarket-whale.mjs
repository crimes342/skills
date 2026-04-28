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
    minVol: { type: 'string', default: '1000000' },   // $1M 最低成交量
    maxRatio: { type: 'string', default: '20' },      // 量/流动性比阈值
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

// ── 获取临近到期事件 ──
async function getExpiringEvents() {
  const now = new Date().toISOString();
  const cutoff = new Date(Date.now() + CONFIG.hoursUntilExpiry * 3600000).toISOString();
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '100',
    order: 'end_date_min', ascending: 'true',
    end_date_min: now, end_date_max: cutoff,
  }));
}

// ── 获取热门事件（按成交量） ──
async function getTrendingEvents() {
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '50',
    order: 'volume', ascending: 'false',
  }));
}

// ── 获取新上市/成交量突增事件 ──
async function getNewHighVolumeEvents() {
  return fetchJSON(`${GAMMA_API}/events?` + new URLSearchParams({
    active: 'true', closed: 'false', limit: '50',
    order: 'volume_num', ascending: 'false',
  }));
}

// ── 分析单个事件 ──
function analyzeEvent(event, category) {
  const vol = Number(event.volume || 0);
  const liq = Number(event.liquidity || 0);
  const hrs = hoursUntil(event.endDate);
  const signals = [];
  const markets = event.markets || [];

  // 价格极端检测
  for (const m of markets) {
    const prices = JSON.parse(m.outcomePrices || '[]');
    const outcomes = JSON.parse(m.outcomes || '[]');
    for (let i = 0; i < prices.length; i++) {
      const p = parseFloat(prices[i]);
      if (p >= 0.95) signals.push({ type: 'PRICE_EXTREME', severity: 'high', detail: `${outcomes[i]}=${fmtPct(prices[i])} (几乎确定)` });
      else if (p <= 0.05 && p > 0) signals.push({ type: 'PRICE_EXTREME_LOW', severity: 'medium', detail: `${outcomes[i]}=${fmtPct(prices[i])} (几乎归零)` });
    }
  }

  // 流动性异常
  if (liq > 0 && vol / liq > CONFIG.anomalyRatio) {
    signals.push({ type: 'VOLUME_SPIKE', severity: 'high', detail: `量/流动性=${(vol / liq).toFixed(1)}x` });
  }

  // 临近到期高额
  if (hrs < 24 && vol > CONFIG.minVolume) {
    signals.push({ type: 'HIGH_VOL_NEAR_EXPIRY', severity: 'critical', detail: `${hrs.toFixed(0)}h内到期 ${fmtMoney(vol)}` });
  }

  // 超大成交量
  if (vol > 10e6) {
    signals.push({ type: 'MEGA_VOLUME', severity: 'high', detail: `成交量 ${fmtMoney(vol)}` });
  }

  // 提取领先结果
  let leading = { outcome: '?', price: 0 };
  for (const m of markets) {
    const p = JSON.parse(m.outcomePrices || '[]');
    const o = JSON.parse(m.outcomes || '[]');
    for (let i = 0; i < p.length; i++) {
      if (parseFloat(p[i]) > leading.price) leading = { outcome: o[i], price: parseFloat(p[i]) };
    }
  }

  return {
    title: event.title,
    slug: event.slug,
    url: `https://polymarket.com/event/${event.slug}`,
    endDate: event.endDate,
    hoursLeft: hrs,
    volume: vol,
    liquidity: liq,
    volumeLiquidityRatio: liq > 0 ? vol / liq : 0,
    leading: leading,
    markets: markets.map(m => ({
      question: m.question,
      outcomes: JSON.parse(m.outcomes || '[]'),
      prices: JSON.parse(m.outcomePrices || '[]'),
    })),
    signals,
    signalCount: signals.length,
    category,
  };
}

// ── 生成文本报告 ──
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
    getExpiringEvents(),
    getTrendingEvents(),
    getNewHighVolumeEvents(),
  ]);

  // 分析所有事件
  const expiringAnalyzed = expiring.map(e => analyzeEvent(e, 'expiring'));
  const trendingAnalyzed = trending.map(e => analyzeEvent(e, 'trending'));
  const newHighVolAnalyzed = newHighVol.map(e => analyzeEvent(e, 'new_high_volume'));

  // 筛选有信号的事件
  const expiringWhales = expiringAnalyzed.filter(r => r.signalCount > 0);
  const trendingWhales = trendingAnalyzed.filter(r => r.signalCount > 0);
  const newWhales = newHighVolAnalyzed.filter(r => r.signalCount > 0);

  // 按严重程度排序
  const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
  const sortBySeverity = (a, b) => {
    const aMin = Math.min(...a.signals.map(s => severityOrder[s.severity] ?? 3));
    const bMin = Math.min(...b.signals.map(s => severityOrder[s.severity] ?? 3));
    return aMin - bMin || b.volume - a.volume;
  };

  expiringWhales.sort(sortBySeverity);
  trendingWhales.sort(sortBySeverity);
  newWhales.sort(sortBySeverity);

  // 输出报告
  console.log(`📊 临近到期: ${expiring.length} | 热门: ${trending.length} | 新高量: ${newHighVol.length}`);
  console.log(`🐋 鲸鱼信号: 临近到期 ${expiringWhales.length} | 热门 ${trendingWhales.length} | 新高量 ${newWhales.length}\n`);

  if (expiringWhales.length) {
    console.log('='.repeat(60));
    console.log('🚨 临近到期 + 巨额异动');
    console.log('='.repeat(60));
    console.log(formatReport(expiringWhales));
  }

  if (trendingWhales.length) {
    console.log('='.repeat(60));
    console.log('🔥 热门市场巨鲸动向');
    console.log('='.repeat(60));
    console.log(formatReport(trendingWhales.slice(0, 15)));
  }

  if (newWhales.length) {
    console.log('='.repeat(60));
    console.log('📈 成交量突增市场');
    console.log('='.repeat(60));
    console.log(formatReport(newWhales.slice(0, 10)));
  }

  // 写入 JSON
  const output = {
    scanTime: new Date().toISOString(),
    config: CONFIG,
    summary: {
      expiringTotal: expiring.length,
      trendingTotal: trending.length,
      newHighVolTotal: newHighVol.length,
      whaleSignals: expiringWhales.length + trendingWhales.length + newWhales.length,
    },
    items: [...expiringWhales, ...trendingWhales, ...newWhales],
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
