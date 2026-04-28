#!/usr/bin/env node
/**
 * Commodity & Traditional Futures Scanner 🛢️🥇
 * 监控大宗商品期货期权异动
 * 数据源：Yahoo Finance + Trading Economics（公开，无需密钥）
 */
import { writeFileSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json: { type: 'string', default: '/tmp/commodity-whale.json' },
  },
  strict: false,
});

const CONFIG = {
  jsonOutput: args.json,
  // 价格异动阈值
  priceChangeWarn: 2,     // 2% → ⚠️
  priceChangeCrit: 5,     // 5% → 🚨
  // 成交量异常倍数
  volumeAnomalyRatio: 2,  // 成交量 > 2倍均值
};

// 大宗商品关键合约
const COMMODITIES = [
  // 贵金属
  { symbol: 'GC=F',  name: '黄金期货',    category: '贵金属', unit: '$/oz' },
  { symbol: 'SI=F',  name: '白银期货',    category: '贵金属', unit: '$/oz' },
  { symbol: 'PL=F',  name: '铂金期货',    category: '贵金属', unit: '$/oz' },
  // 能源
  { symbol: 'CL=F',  name: 'WTI原油期货', category: '能源', unit: '$/桶' },
  { symbol: 'BZ=F',  name: '布伦特原油',  category: '能源', unit: '$/桶' },
  { symbol: 'NG=F',  name: '天然气期货',  category: '能源', unit: '$/MMBtu' },
  // 工业金属
  { symbol: 'HG=F',  name: '铜期货',      category: '工业金属', unit: '$/lb' },
  // 农产品
  { symbol: 'ZC=F',  name: '玉米期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'ZS=F',  name: '大豆期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'ZW=F',  name: '小麦期货',    category: '农产品', unit: '$/bu' },
  { symbol: 'CT=F',  name: '棉花期货',    category: '农产品', unit: '$/lb' },
  { symbol: 'KC=F',  name: '咖啡期货',    category: '农产品', unit: '$/lb' },
  { symbol: 'SB=F',  name: '糖期货',      category: '农产品', unit: '$/lb' },
  // 股指期货（补充）
  { symbol: 'ES=F',  name: '标普500期货', category: '股指', unit: '点' },
  { symbol: 'NQ=F',  name: '纳斯达克期货',category: '股指', unit: '点' },
  { symbol: 'YM=F',  name: '道琼斯期货',  category: '股指', unit: '点' },
  { symbol: 'NKD=F', name: '日经225期货', category: '股指', unit: '点' },
  // 国债
  { symbol: 'ZB=F',  name: '美国国债期货',category: '国债', unit: '点' },
  { symbol: 'ZN=F',  name: '10年期国债',  category: '国债', unit: '点' },
  // 外汇
  { symbol: 'DX=F',  name: '美元指数期货',category: '外汇', unit: '点' },
  { symbol: '6E=F',  name: '欧元期货',    category: '外汇', unit: '' },
  { symbol: '6J=F',  name: '日元期货',    category: '外汇', unit: '' },
];

async function fetchYahooQuote(symbol) {
  try {
    const url = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=5d`;
    const resp = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0' },
      signal: AbortSignal.timeout(10000),
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    const result = data.chart?.result?.[0];
    if (!result) return null;

    const meta = result.meta;
    const quotes = result.indicators?.quote?.[0];
    const timestamps = result.timestamp || [];

    const currentPrice = meta.regularMarketPrice || 0;
    const prevClose = meta.chartPreviousClose || meta.previousClose || 0;
    const change = prevClose ? ((currentPrice - prevClose) / prevClose * 100) : 0;

    // 获取近5日成交量
    const volumes = (quotes?.volume || []).filter(v => v > 0);
    const avgVolume = volumes.length > 1
      ? volumes.slice(0, -1).reduce((a, b) => a + b, 0) / (volumes.length - 1)
      : 0;
    const latestVolume = volumes[volumes.length - 1] || 0;

    // 日内高低
    const highs = (quotes?.high || []).filter(v => v > 0);
    const lows = (quotes?.low || []).filter(v => v > 0);
    const dayHigh = highs[highs.length - 1] || currentPrice;
    const dayLow = lows[lows.length - 1] || currentPrice;
    const amplitude = dayLow > 0 ? ((dayHigh - dayLow) / dayLow * 100) : 0;

    return {
      symbol,
      price: currentPrice,
      prevClose,
      change: change.toFixed(2) + '%',
      changeNum: change,
      dayHigh,
      dayLow,
      amplitude: amplitude.toFixed(2) + '%',
      amplitudeNum: amplitude,
      volume: latestVolume,
      avgVolume,
      volumeRatio: avgVolume > 0 ? (latestVolume / avgVolume).toFixed(2) : 'N/A',
      volumeRatioNum: avgVolume > 0 ? latestVolume / avgVolume : 0,
    };
  } catch (e) {
    console.error(`   ⚠️ ${symbol}: ${e.message}`);
    return null;
  }
}

function analyzeQuote(quote, commodity) {
  if (!quote) return null;

  const signals = [];
  const absChange = Math.abs(quote.changeNum);
  const absAmplitude = Math.abs(quote.amplitudeNum);

  // 价格异动
  if (absChange >= CONFIG.priceChangeCrit) {
    signals.push({
      type: 'PRICE_MOVE',
      severity: 'critical',
      detail: `24h变化 ${quote.changeNum > 0 ? '+' : ''}${quote.change}%`,
    });
  } else if (absChange >= CONFIG.priceChangeWarn) {
    signals.push({
      type: 'PRICE_MOVE',
      severity: 'high',
      detail: `24h变化 ${quote.changeNum > 0 ? '+' : ''}${quote.change}%`,
    });
  }

  // 振幅异常
  if (absAmplitude >= 5) {
    signals.push({
      type: 'HIGH_AMPLITUDE',
      severity: 'high',
      detail: `日内振幅 ${quote.amplitude}%`,
    });
  }

  // 成交量异常
  if (quote.volumeRatioNum >= CONFIG.volumeAnomalyRatio) {
    signals.push({
      type: 'VOLUME_SPIKE',
      severity: quote.volumeRatioNum >= 3 ? 'critical' : 'high',
      detail: `成交量 ${quote.volumeRatio}x 均值`,
    });
  }

  return {
    ...commodity,
    price: quote.price,
    prevClose: quote.prevClose,
    change: quote.change,
    changeNum: quote.changeNum,
    dayHigh: quote.dayHigh,
    dayLow: quote.dayLow,
    amplitude: quote.amplitude,
    volume: quote.volume,
    avgVolume: quote.avgVolume,
    volumeRatio: quote.volumeRatio,
    signals,
    signalCount: signals.length,
    severity: signals.some(s => s.severity === 'critical') ? 'critical'
            : signals.some(s => s.severity === 'high') ? 'high' : 'normal',
  };
}

function formatMoney(n) {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(0)}K`;
  return `${n.toFixed(0)}`;
}

function formatReport(results) {
  const lines = [];
  const byCategory = {};

  for (const r of results) {
    if (!byCategory[r.category]) byCategory[r.category] = [];
    byCategory[r.category].push(r);
  }

  for (const [cat, items] of Object.entries(byCategory)) {
    const hasAlerts = items.some(i => i.signalCount > 0);
    const emoji = { '贵金属': '🥇', '能源': '🛢️', '工业金属': '⚙️', '农产品': '🌾', '股指': '📊', '国债': '📜', '外汇': '💱' }[cat] || '📌';

    lines.push(`${emoji} ${cat}`);
    lines.push('─'.repeat(40));

    for (const item of items) {
      const alertEmoji = item.severity === 'critical' ? '🚨' : item.severity === 'high' ? '⚠️' : '  ';
      const changeStr = item.changeNum >= 0 ? `+${item.change}` : item.change;
      const priceStr = item.price >= 1000 ? item.price.toFixed(0) : item.price >= 1 ? item.price.toFixed(2) : item.price.toFixed(4);

      lines.push(`${alertEmoji} ${item.name.padEnd(12)} ${priceStr} ${item.unit}  (${changeStr})`);

      if (item.signals.length) {
        for (const s of item.signals) {
          lines.push(`      → ${s.detail}`);
        }
      }
    }
    lines.push('');
  }

  return lines.join('\n');
}

async function main() {
  console.error(`🛢️ Commodity Scanner | ${new Date().toISOString()}`);
  console.error(`   扫描 ${COMMODITIES.length} 个合约...`);

  // 批量请求（分批避免限流）
  const results = [];
  const batchSize = 5;
  for (let i = 0; i < COMMODITIES.length; i += batchSize) {
    const batch = COMMODITIES.slice(i, i + batchSize);
    const quotes = await Promise.all(batch.map(c => fetchYahooQuote(c.symbol)));
    for (let j = 0; j < batch.length; j++) {
      const analyzed = analyzeQuote(quotes[j], batch[j]);
      if (analyzed) results.push(analyzed);
    }
    // 小延迟避免限流
    if (i + batchSize < COMMODITIES.length) {
      await new Promise(r => setTimeout(r, 500));
    }
  }

  const critical = results.filter(r => r.severity === 'critical');
  const high = results.filter(r => r.severity === 'high');
  const withSignals = results.filter(r => r.signalCount > 0);

  // 输出报告
  console.log(`\n📊 扫描完成 | ${new Date().toISOString()}`);
  console.log(`   合约: ${results.length} | 🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  if (withSignals.length) {
    console.log('═'.repeat(50));
    console.log('🚨 大宗商品异动信号');
    console.log('═'.repeat(50));
    console.log('');
    for (const item of withSignals) {
      const emoji = item.severity === 'critical' ? '🚨' : '⚠️';
      console.log(`${emoji} ${item.name} (${item.symbol})`);
      console.log(`   价格: ${item.price} ${item.unit} | 变化: ${item.change} | 振幅: ${item.amplitude}`);
      console.log(`   成交量: ${formatMoney(item.volume)} | 均值: ${formatMoney(item.avgVolume)} | 比率: ${item.volumeRatio}x`);
      for (const s of item.signals) {
        console.log(`   📌 ${s.type}: ${s.detail}`);
      }
      console.log('');
    }
  }

  console.log('═'.repeat(50));
  console.log('📋 全部合约行情');
  console.log('═'.repeat(50));
  console.log('');
  console.log(formatReport(results));

  // 写入 JSON
  const output = {
    scanTime: new Date().toISOString(),
    summary: {
      total: results.length,
      critical: critical.length,
      high: high.length,
      withSignals: withSignals.length,
    },
    alerts: withSignals.map(r => ({
      symbol: r.symbol,
      name: r.name,
      category: r.category,
      price: r.price,
      change: r.change,
      amplitude: r.amplitude,
      volumeRatio: r.volumeRatio,
      signals: r.signals,
      severity: r.severity,
    })),
    items: results.map(r => ({
      symbol: r.symbol,
      name: r.name,
      category: r.category,
      price: r.price,
      change: r.change,
      amplitude: r.amplitude,
      volume: r.volume,
      avgVolume: r.avgVolume,
      volumeRatio: r.volumeRatio,
      signals: r.signals,
    })),
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
