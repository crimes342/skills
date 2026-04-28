#!/usr/bin/env node
/**
 * Daily Summary Generator 📋
 * 生成前一日市场异常检测总结
 * 读取历史 JSON 数据，汇总 Critical/High 信号
 */
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'fs';
import { parseArgs } from 'util';

const { values: args } = parseArgs({
  options: {
    date:    { type: 'string', default: 'yesterday' },
    json:    { type: 'string', default: '/tmp/daily-summary.json' },
    dataDir: { type: 'string', default: '/tmp' },
  },
  strict: false,
});

function getDateRange(dateArg) {
  const now = new Date();
  let target;
  if (dateArg === 'yesterday') {
    target = new Date(now.getTime() - 86400000);
  } else if (dateArg === 'today') {
    target = now;
  } else {
    target = new Date(dateArg);
  }
  const yyyy = target.getFullYear();
  const mm = String(target.getMonth() + 1).padStart(2, '0');
  const dd = String(target.getDate()).padStart(2, '0');
  return {
    dateStr: `${yyyy}-${mm}-${dd}`,
    start: new Date(`${yyyy}-${mm}-${dd}T00:00:00Z`),
    end: new Date(`${yyyy}-${mm}-${dd}T23:59:59Z`),
  };
}

function loadJsonSafe(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

function findDataFiles(dataDir, dateStr) {
  const patterns = [
    `polymarket-whale`,
    `crypto-whale`,
    `futures-whale`,
    `market-whale`,
  ];
  const files = [];
  try {
    const allFiles = readdirSync(dataDir);
    for (const f of allFiles) {
      if (f.endsWith('.json') && patterns.some(p => f.includes(p))) {
        files.push(`${dataDir}/${f}`);
      }
    }
  } catch {}
  return files;
}

function classifySignal(severity) {
  if (severity === 'critical') return '🚨 Critical';
  if (severity === 'high') return '⚠️ High';
  if (severity === 'medium') return '📌 Medium';
  return '📊 Info';
}

function buildSummary(data, source) {
  const items = data.items || [];
  const critical = items.filter(i =>
    i.severity === 'critical' ||
    (i.signals && i.signals.some(s => s.severity === 'critical'))
  );
  const high = items.filter(i =>
    i.severity === 'high' ||
    (i.signals && i.signals.some(s => s.severity === 'high'))
  );

  return {
    source,
    totalItems: items.length,
    criticalCount: critical.length,
    highCount: high.length,
    criticalItems: critical.slice(0, 10).map(i => ({
      title: i.title || i.symbol || i.instrument || 'Unknown',
      type: i.type || 'UNKNOWN',
      detail: i.detail || i.analysis || '',
      volume: i.volume || i.volume24h || i.notional || 0,
      url: i.url || '',
      signals: (i.signals || []).map(s => s.detail).join('; '),
    })),
    highItems: high.slice(0, 10).map(i => ({
      title: i.title || i.symbol || i.instrument || 'Unknown',
      type: i.type || 'UNKNOWN',
      detail: i.detail || i.analysis || '',
      volume: i.volume || i.volume24h || i.notional || 0,
      url: i.url || '',
    })),
    scanTime: data.scanTime || null,
  };
}

function formatMoney(n) {
  n = Number(n || 0);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

function generateTextReport(summaries, dateRange) {
  const lines = [
    `📋 市场异常日报 | ${dateRange.dateStr}`,
    '═'.repeat(50),
    '',
  ];

  // 总览
  let totalCritical = 0, totalHigh = 0, totalItems = 0;
  for (const s of summaries) {
    totalCritical += s.criticalCount;
    totalHigh += s.highCount;
    totalItems += s.totalItems;
  }

  lines.push(`📊 统计总览`);
  lines.push(`   扫描文件: ${summaries.length} 个`);
  lines.push(`   总信号数: ${totalItems}`);
  lines.push(`   🚨 Critical: ${totalCritical}`);
  lines.push(`   ⚠️ High: ${totalHigh}`);
  lines.push('');

  // Polymarket
  const poly = summaries.find(s => s.source === 'polymarket');
  if (poly && poly.criticalItems.length) {
    lines.push('🎰 Polymarket 异常 Top 5');
    lines.push('─'.repeat(40));
    for (const item of poly.criticalItems.slice(0, 5)) {
      lines.push(`   🚨 ${item.title}`);
      lines.push(`      成交量: ${formatMoney(item.volume)} | ${item.type}`);
      if (item.detail) lines.push(`      ${item.detail}`);
      if (item.url) lines.push(`      🔗 ${item.url}`);
      lines.push('');
    }
  }

  // Crypto
  const crypto = summaries.find(s => s.source === 'crypto');
  if (crypto && (crypto.criticalItems.length || crypto.highItems.length)) {
    lines.push('₿ 加密市场异动 Top 5');
    lines.push('─'.repeat(40));
    const allItems = [...crypto.criticalItems, ...crypto.highItems];
    for (const item of allItems.slice(0, 5)) {
      const emoji = crypto.criticalItems.includes(item) ? '🚨' : '⚠️';
      lines.push(`   ${emoji} ${item.title} | ${item.type}`);
      if (item.detail) lines.push(`      ${item.detail}`);
      lines.push('');
    }
  }

  // Futures
  const futures = summaries.find(s => s.source === 'futures');
  if (futures && (futures.criticalItems.length || futures.highItems.length)) {
    lines.push('📈 期货期权异动 Top 5');
    lines.push('─'.repeat(40));
    const allItems = [...futures.criticalItems, ...futures.highItems];
    for (const item of allItems.slice(0, 5)) {
      const emoji = futures.criticalItems.includes(item) ? '🚨' : '⚠️';
      lines.push(`   ${emoji} ${item.title} | ${item.type}`);
      if (item.detail) lines.push(`      ${item.detail}`);
      lines.push('');
    }
  }

  if (totalCritical === 0 && totalHigh === 0) {
    lines.push('✅ 昨日无重大异常信号，市场整体平稳。');
  }

  return lines.join('\n');
}

async function main() {
  const dateRange = getDateRange(args.date);
  console.error(`📋 Daily Summary | ${dateRange.dateStr}`);

  // 尝试加载历史数据文件
  const dataDir = args.dataDir;
  const dataFiles = findDataFiles(dataDir, dateRange.dateStr);

  const summaries = [];

  // 加载各类数据
  const sources = [
    { file: `${dataDir}/polymarket-whale.json`, name: 'polymarket' },
    { file: `${dataDir}/crypto-whale.json`, name: 'crypto' },
    { file: `${dataDir}/futures-whale.json`, name: 'futures' },
  ];

  for (const src of sources) {
    const data = loadJsonSafe(src.file);
    if (data) {
      summaries.push(buildSummary(data, src.name));
      console.error(`   ✅ 加载 ${src.name}: ${data.items?.length || 0} 条记录`);
    } else {
      console.error(`   ⚠️ ${src.name}: 无数据文件`);
    }
  }

  // 也扫描 /tmp 下可能存在的带时间戳的文件
  for (const f of dataFiles) {
    const data = loadJsonSafe(f);
    if (data && data.items?.length) {
      const source = f.includes('polymarket') ? 'polymarket' :
                     f.includes('crypto') ? 'crypto' :
                     f.includes('futures') ? 'futures' : 'unknown';
      // 避免重复
      if (!summaries.find(s => s.source === source)) {
        summaries.push(buildSummary(data, source));
      }
    }
  }

  // 生成报告
  const textReport = generateTextReport(summaries, dateRange);
  console.log(textReport);

  // 写入 JSON
  const output = {
    date: dateRange.dateStr,
    generatedAt: new Date().toISOString(),
    summaries,
    totalCritical: summaries.reduce((s, x) => s + x.criticalCount, 0),
    totalHigh: summaries.reduce((s, x) => s + x.highCount, 0),
  };

  writeFileSync(args.json, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${args.json}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
