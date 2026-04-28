#!/usr/bin/env node
/**
 * Smart Scheduler 🧠⏰
 * 智能调度器：根据市场状态和异常严重程度决定推送频率
 * 输出建议的下次执行时间、间隔和推送级别
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    json:        { type: 'string', default: '/tmp/market-whale-scheduler.json' },
    stateFile:   { type: 'string', default: '/tmp/market-whale-state.json' },
    polyFile:    { type: 'string', default: '/tmp/polymarket-whale.json' },
    cryptoFile:  { type: 'string', default: '/tmp/crypto-whale.json' },
    futuresFile: { type: 'string', default: '/tmp/futures-whale.json' },
    commodityFile:{ type: 'string', default: '/tmp/commodity-whale.json' },
  },
  strict: false,
});

// ══════════════════════════════════════════
// 交易时段定义 (UTC)
// ══════════════════════════════════════════
const MARKET_HOURS = {
  US_STOCK:     { open: '13:30', close: '20:00', label: '美股' },
  US_FUTURES:   { open: '23:00', close: '22:00', label: '美国期货(近24h)' },
  EU_STOCK:     { open: '08:00', close: '16:30', label: '欧股' },
  ASIA_STOCK:   { open: '00:00', close: '08:00', label: '亚洲股市' },
  CRYPTO:       { open: '00:00', close: '23:59', label: '加密货币(24/7)' },
  POLYMARKET:   { open: '00:00', close: '23:59', label: 'Polymarket(24/7)' },
};

// ══════════════════════════════════════════
// 频率规则
// ══════════════════════════════════════════
const INTERVALS = {
  CRITICAL:  { minutes: 5,  label: '5m',  urgency: 'critical' },
  HIGH:      { minutes: 15, label: '15m', urgency: 'high' },
  NORMAL:    { minutes: 30, label: '30m', urgency: 'normal' },
  ROUTINE:   { minutes: 60, label: '1h',  urgency: 'routine' },
  LOW:       { minutes: 240,label: '4h',  urgency: 'low' },
};

function loadJsonSafe(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

function loadState() {
  const state = loadJsonSafe(args.stateFile);
  return state || {
    lastRun: null,
    lastInterval: null,
    consecutiveCalm: 0,
    alertHistory: [],
  };
}

function saveState(state) {
  writeFileSync(args.stateFile, JSON.stringify(state, null, 2));
}

function hoursUntil(dateStr) {
  return (new Date(dateStr).getTime() - Date.now()) / 3600000;
}

function isMarketOpen(marketKey) {
  const market = MARKET_HOURS[marketKey];
  if (!market) return false;
  if (market.open === '00:00' && market.close === '23:59') return true;

  const now = new Date();
  const utcH = now.getUTCHours();
  const utcM = now.getUTCMinutes();
  const nowMin = utcH * 60 + utcM;

  const [oH, oM] = market.open.split(':').map(Number);
  const [cH, cM] = market.close.split(':').map(Number);
  const openMin = oH * 60 + oM;
  const closeMin = cH * 60 + cM;

  if (openMin < closeMin) {
    return nowMin >= openMin && nowMin <= closeMin;
  } else {
    return nowMin >= openMin || nowMin <= closeMin;
  }
}

function getOpenMarkets() {
  return Object.entries(MARKET_HOURS)
    .filter(([key]) => isMarketOpen(key))
    .map(([key, m]) => m.label);
}

// ══════════════════════════════════════════
// 异常分析
// ══════════════════════════════════════════
function analyzeExpirations(polyData) {
  const reasons = [];
  let closestExpiry = Infinity;

  if (!polyData?.items) return { reasons, closestExpiry };

  for (const item of polyData.items) {
    const hrs = item.hoursLeft ?? hoursUntil(item.endDate);
    if (hrs < 0) continue; // 已过期

    const vol = item.volume || 0;

    if (hrs <= 1) {
      closestExpiry = Math.min(closestExpiry, hrs);
      reasons.push(`${item.title} ${hrs.toFixed(1)}h内到期 (${(vol/1e6).toFixed(1)}M)`);
    } else if (hrs <= 6 && vol > 10e6) {
      closestExpiry = Math.min(closestExpiry, hrs);
      reasons.push(`${item.title} ${hrs.toFixed(1)}h内到期 (${(vol/1e6).toFixed(1)}M)`);
    } else if (hrs <= 24 && vol > 1e6) {
      closestExpiry = Math.min(closestExpiry, hrs);
    }
  }

  return { reasons, closestExpiry };
}

function analyzeCryptoSignals(cryptoData) {
  const reasons = [];
  if (!cryptoData?.items) return reasons;

  for (const item of cryptoData.items) {
    if (item.severity === 'critical') {
      reasons.push(`${item.symbol || item.chain} ${item.type} (Critical)`);
    }
  }
  return reasons;
}

function analyzeFuturesSignals(futuresData) {
  const reasons = [];
  if (!futuresData?.items) return reasons;

  for (const item of futuresData.items) {
    if (item.severity === 'critical') {
      const detail = item.fundingRate
        ? `费率${item.fundingRate}`
        : item.detail || '';
      reasons.push(`${item.symbol} ${item.type} ${detail} (Critical)`);
    }
    // 期权到期临近
    if (item.type === 'OPTIONS_EXPIRY') {
      const match = item.detail?.match(/(\d+)(\w{3})(\d{2})/);
      if (match) {
        // 粗略计算到期时间
        reasons.push(`${item.symbol} 大额到期 ${item.detail}`);
      }
    }
  }
  return reasons;
}

function analyzeOptionExpiries(futuresData) {
  let closestExpiry = Infinity;
  if (!futuresData?.items) return closestExpiry;

  for (const item of futuresData.items) {
    if (item.type === 'OPTIONS_EXPIRY' && item.expiry) {
      // Deribit 日期格式: 28APR26
      const months = { JAN:0,FEB:1,MAR:2,APR:3,MAY:4,JUN:5,JUL:6,AUG:7,SEP:8,OCT:9,NOV:10,DEC:11 };
      const match = item.expiry.match(/(\d{2})(\w{3})(\d{2})/);
      if (match) {
        const day = parseInt(match[1]);
        const month = months[match[2]];
        const year = 2000 + parseInt(match[3]);
        if (month !== undefined) {
          const expiryDate = new Date(Date.UTC(year, month, day, 23, 59, 59));
          const hrs = (expiryDate.getTime() - Date.now()) / 3600000;
          if (hrs > 0 && hrs < closestExpiry) closestExpiry = hrs;
        }
      }
    }
  }
  return closestExpiry;
}

function analyzeCommoditySignals(commodityData) {
  const reasons = [];
  if (!commodityData?.items) return reasons;

  for (const item of commodityData.items) {
    if (item.severity === 'critical') {
      reasons.push(`${item.name} ${item.type || ''} ${item.change || ''} (Critical)`);
    }
  }
  return reasons;
}

// ══════════════════════════════════════════
// 主调度逻辑
// ══════════════════════════════════════════
function determineInterval(polyData, cryptoData, futuresData, commodityData, state) {
  const reasons = [];
  let interval = INTERVALS.LOW;
  let closestExpiry = Infinity;

  // 1. 检查 Polymarket 到期
  const polyAnalysis = analyzeExpirations(polyData);
  reasons.push(...polyAnalysis.reasons);
  closestExpiry = Math.min(closestExpiry, polyAnalysis.closestExpiry);

  // 2. 检查加密市场
  const cryptoReasons = analyzeCryptoSignals(cryptoData);
  reasons.push(...cryptoReasons);

  // 3. 检查期货期权
  const futuresReasons = analyzeFuturesSignals(futuresData);
  reasons.push(...futuresReasons);

  // 3.5 检查大宗商品
  const commodityReasons = analyzeCommoditySignals(commodityData);
  reasons.push(...commodityReasons);

  // 4. 检查期权到期
  const optionExpiry = analyzeOptionExpiries(futuresData);
  closestExpiry = Math.min(closestExpiry, optionExpiry);

  // 5. 判断频率
  if (closestExpiry <= 1 || reasons.length >= 5) {
    interval = INTERVALS.CRITICAL;
  } else if (closestExpiry <= 6 || reasons.length >= 3) {
    interval = INTERVALS.HIGH;
  } else if (closestExpiry <= 24 || reasons.length >= 1) {
    interval = INTERVALS.NORMAL;
  } else if (isMarketOpen('US_STOCK') || isMarketOpen('EU_STOCK')) {
    interval = INTERVALS.ROUTINE;
  } else {
    interval = INTERVALS.LOW;
  }

  // 6. 连续平静则降频
  if (reasons.length === 0) {
    state.consecutiveCalm = (state.consecutiveCalm || 0) + 1;
    if (state.consecutiveCalm >= 3 && interval.minutes < INTERVALS.ROUTINE.minutes) {
      interval = INTERVALS.ROUTINE;
    }
  } else {
    state.consecutiveCalm = 0;
  }

  return { interval, reasons, closestExpiry };
}

function buildSchedule(interval, reasons, closestExpiry, openMarkets) {
  const now = new Date();
  const nextRun = new Date(now.getTime() + interval.minutes * 60000);

  return {
    currentTime: now.toISOString(),
    nextRun: nextRun.toISOString(),
    interval: interval.label,
    intervalMinutes: interval.minutes,
    urgency: interval.urgency,
    reasons: reasons.slice(0, 8),
    reasonCount: reasons.length,
    closestExpiryHours: closestExpiry === Infinity ? null : closestExpiry.toFixed(1),
    openMarkets,
    consecutiveCalm: 0,
  };
}

function formatReport(schedule) {
  const urgencyEmoji = {
    critical: '🚨',
    high: '⚠️',
    normal: '📌',
    routine: '📊',
    low: '💤',
  };

  const lines = [
    `⏰ 调度建议 | ${schedule.currentTime}`,
    '─'.repeat(40),
    `${urgencyEmoji[schedule.urgency]} 级别: ${schedule.urgency.toUpperCase()}`,
    `⏱️ 下次扫描: ${schedule.nextRun}`,
    `🔄 间隔: ${schedule.interval}`,
    '',
  ];

  if (schedule.closestExpiryHours) {
    lines.push(`⏳ 最近到期: ${schedule.closestExpiryHours}h`);
  }

  if (schedule.openMarkets.length) {
    lines.push(`🏪 开盘市场: ${schedule.openMarkets.join(', ')}`);
  }

  if (schedule.reasons.length) {
    lines.push('');
    lines.push(`📋 触发原因 (${schedule.reasonCount}):`);
    for (const r of schedule.reasons) {
      lines.push(`   • ${r}`);
    }
  } else {
    lines.push('');
    lines.push('✅ 当前无异常信号');
  }

  return lines.join('\n');
}

async function main() {
  const state = loadState();

  // 加载最新数据
  const polyData = loadJsonSafe(args.polyFile);
  const cryptoData = loadJsonSafe(args.cryptoFile);
  const futuresData = loadJsonSafe(args.futuresFile);
  const commodityData = loadJsonSafe(args.commodityFile);

  const openMarkets = getOpenMarkets();
  const { interval, reasons, closestExpiry } = determineInterval(
    polyData, cryptoData, futuresData, commodityData, state
  );

  const schedule = buildSchedule(interval, reasons, closestExpiry, openMarkets);

  // 更新状态
  state.lastRun = schedule.currentTime;
  state.lastInterval = schedule.interval;
  state.consecutiveCalm = reasons.length === 0 ? (state.consecutiveCalm || 0) + 1 : 0;
  saveState(state);

  // 输出
  console.log(formatReport(schedule));

  writeFileSync(args.json, JSON.stringify(schedule, null, 2));
  console.error(`\n📁 JSON → ${args.json}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
