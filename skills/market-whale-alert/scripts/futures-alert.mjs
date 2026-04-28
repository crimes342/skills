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
    liqMin:     { type: 'string', default: '10000000' },  // 爆仓阈值 $10M
    fundRateHi: { type: 'string', default: '0.001' },     // 资金费率上限 0.1%
    fundRateLo: { type: 'string', default: '-0.0005' },   // 资金费率下限 -0.05%
    oiChangePct:{ type: 'string', default: '10' },        // OI 变化百分比阈值
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
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: { 'Accept': 'application/json' },
    });
    clearTimeout(timer);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.json();
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

function fmtMoney(n) {
  n = Number(n);
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

// ══════════════════════════════════════════
// 模块1: Binance Futures 异常检测
// ══════════════════════════════════════════
async function scanBinanceFutures() {
  const alerts = [];

  try {
    // 1. 资金费率异常
    const fundingRates = await fetchJSON('https://fapi.binance.com/fapi/v1/premiumIndex');
    for (const fr of fundingRates) {
      const rate = parseFloat(fr.lastFundingRate || 0);
      const markPrice = parseFloat(fr.markPrice || 0);
      const sym = fr.symbol || 'UNKNOWN';

      if (rate > CONFIG.fundingRateHigh) {
        alerts.push({
          exchange: 'Binance', symbol: sym,
          type: 'FUNDING_RATE_HIGH', severity: rate > 0.003 ? 'critical' : 'high',
          detail: `资金费率 ${(rate * 100).toFixed(4)}%（多头付费）`,
          markPrice, fundingRate: rate,
          nextFunding: new Date(fr.nextFundingTime).toISOString(),
          interpretation: '多头过热，空头在收割多头资金费',
        });
      } else if (rate < CONFIG.fundingRateLow) {
        alerts.push({
          exchange: 'Binance', symbol: sym,
          type: 'FUNDING_RATE_LOW', severity: Math.abs(rate) > 0.002 ? 'critical' : 'high',
          detail: `资金费率 ${(rate * 100).toFixed(4)}%（空头付费）`,
          markPrice, fundingRate: rate,
          nextFunding: new Date(fr.nextFundingTime).toISOString(),
          interpretation: '空头过热，多头在收割空头资金费',
        });
      }
    }

    // 2. 价格剧烈波动 + 成交量放大
    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');
    for (const t of tickers) {
      const sym = t.symbol || 'UNKNOWN';
      const priceChange = parseFloat(t.priceChangePercent || 0);
      const vol = parseFloat(t.quoteVolume || 0);
      const highPrice = parseFloat(t.highPrice || 0);
      const lowPrice = parseFloat(t.lowPrice || 0);
      const lastPrice = parseFloat(t.lastPrice || 0);

      // 振幅 > 15% 且成交量大
      const amplitude = highPrice > 0 ? ((highPrice - lowPrice) / lowPrice * 100) : 0;
      if (amplitude > 15 && vol > 50e6) {
        alerts.push({
          exchange: 'Binance', symbol: sym,
          type: 'EXTREME_VOLATILITY', severity: amplitude > 30 ? 'critical' : 'high',
          detail: `振幅 ${amplitude.toFixed(1)}% | 24h变化 ${priceChange.toFixed(2)}%`,
          price: lastPrice, high24h: highPrice, low24h: lowPrice,
          volume24h: vol, volumeStr: fmtMoney(vol),
          interpretation: priceChange > 0 ? '多头主导暴涨' : '空头主导暴跌',
        });
      }

      // 成交量/市值比异常（仅针对主要币种）
      if (['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'].includes(sym) && vol > 1e9) {
        alerts.push({
          exchange: 'Binance', symbol: sym,
          type: 'MEGA_VOLUME', severity: vol > 10e9 ? 'critical' : 'high',
          detail: `24h成交量 ${fmtMoney(vol)}`,
          price: lastPrice, priceChange: priceChange.toFixed(2) + '%',
          volume24h: vol,
          interpretation: '巨量交易，可能有大资金进出',
        });
      }
    }

    // 3. 合约持仓量（Top 币种）
    const topSymbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'BNBUSDT'];
    for (const sym of topSymbols) {
      try {
        const oi = await fetchJSON(`https://fapi.binance.com/fapi/v1/openInterest?symbol=${sym}`);
        alerts.push({
          exchange: 'Binance', symbol: sym,
          type: 'OPEN_INTEREST', severity: 'info',
          detail: `持仓量 ${parseFloat(oi.openInterest).toFixed(2)} 张`,
          openInterest: parseFloat(oi.openInterest),
          time: new Date().toISOString(),
        });
      } catch (e) { /* skip */ }
    }

    // 4. 大户账户多空比
    try {
      const topTraders = await fetchJSON('https://fapi.binance.com/futures/data/topLongShortPositionRatio?symbol=BTCUSDT&period=1h&limit=1');
      if (topTraders.length) {
        const latest = topTraders[0];
        const longRatio = parseFloat(latest.longAccount || 0);
        const shortRatio = parseFloat(latest.shortAccount || 0);
        alerts.push({
          exchange: 'Binance', symbol: 'BTCUSDT',
          type: 'TOP_TRADER_RATIO', severity: 'info',
          detail: `大户多空比 ${longRatio.toFixed(2)} : ${shortRatio.toFixed(2)}`,
          longRatio, shortRatio,
          time: new Date(latest.timestamp).toISOString(),
          interpretation: longRatio > 0.6 ? '大户偏多' : shortRatio > 0.6 ? '大户偏空' : '多空均衡',
        });
      }
    } catch (e) { /* skip */ }

  } catch (e) {
    console.error(`⚠️ Binance Futures 扫描失败: ${e.message}`);
  }

  return alerts;
}

// ══════════════════════════════════════════
// 模块2: Deribit 期权大额监控
// ══════════════════════════════════════════
async function scanDeribitOptions() {
  const alerts = [];

  try {
    // 获取 BTC 和 ETH 期权摘要
    for (const currency of ['BTC', 'ETH']) {
      // 获取期权到期日列表（返回嵌套结构）
      const expiriesResp = await fetchJSON(
        `https://www.deribit.com/api/v2/public/get_expirations?currency=${currency}&kind=option`
      );
      const expiryDates = expiriesResp.result?.[currency.toLowerCase()]?.option || [];
      if (!Array.isArray(expiryDates) || expiryDates.length === 0) {
        console.error(`⚠️ Deribit ${currency}: 无到期日数据`);
        continue;
      }

      // 获取最近到期的期权数据
      for (const expiry of expiryDates.slice(0, 3)) {
        try {
          const bookSummary = await fetchJSON(
            `https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=${currency}&kind=option&expiration=${expiry}`
          );
          const instruments = bookSummary.result || [];

          let totalVolume = 0;
          let totalOI = 0;
          let largeContracts = [];

          for (const inst of instruments) {
            const vol = inst.volume || 0;
            const oi = inst.open_interest || 0;
            const underlyingPrice = inst.underlying_price || 0;
            const notionalValue = oi * underlyingPrice;

            totalVolume += vol;
            totalOI += oi;

            // 大额合约（持仓量 * 标的价格 > $50M）
            if (notionalValue > 50e6) {
              largeContracts.push({
                instrument: inst.instrument_name,
                openInterest: oi,
                volume: vol,
                notionalValue,
                notionalStr: fmtMoney(notionalValue),
                putCall: inst.instrument_name.includes('-P') ? 'PUT' : 'CALL',
              });
            }
          }

          // 总名义价值
          const avgPrice = instruments.length > 0 ? (instruments[0]?.underlying_price || 0) : 0;
          const totalNotional = totalOI * avgPrice;

          if (totalNotional > 100e6) {
            alerts.push({
              exchange: 'Deribit', symbol: `${currency}期权`,
              type: 'OPTIONS_EXPIRY', severity: totalNotional > 1e9 ? 'critical' : 'high',
              detail: `${expiry} 到期 | 名义价值 ${fmtMoney(totalNotional)} | OI ${totalOI.toFixed(0)} 张`,
              expiry, totalOI, totalVolume, totalNotional,
              largeContracts: largeContracts.slice(0, 5),
              interpretation: '大额期权到期，可能引发标的资产波动',
            });
          }
        } catch (e) { /* skip individual expiry */ }
      }

      // 获取大额交易
      try {
        const lastTrade = await fetchJSON(
          `https://www.deribit.com/api/v2/public/get_last_trades_by_currency?currency=${currency}&kind=option&count=50&sorting=desc`
        );
        const trades = lastTrade.result?.trades || [];
        for (const trade of trades) {
          const amount = trade.amount || 0;
          const price = trade.price || 0;
          const indexPrice = trade.index_price || 0;
          // Deribit options: amount 是 BTC/ETH 数量
          const notional = amount * indexPrice;

          if (notional > 1e6) { // > $1M 单笔
            alerts.push({
              exchange: 'Deribit', symbol: trade.instrument_name,
              type: 'OPTIONS_LARGE_TRADE', severity: notional > 50e6 ? 'critical' : notional > 10e6 ? 'high' : 'medium',
              detail: `${trade.direction?.toUpperCase()} ${amount} ${currency} @ $${price} | 名义 ${fmtMoney(notional)}`,
              amount, price, notional, direction: trade.direction,
              time: new Date(trade.timestamp).toISOString(),
            });
          }
        }
      } catch (e) { /* skip */ }
    }
  } catch (e) {
    console.error(`⚠️ Deribit 扫描失败: ${e.message}`);
  }

  return alerts;
}

// ══════════════════════════════════════════
// 模块3: 跨市场清算估算
// ══════════════════════════════════════════
async function estimateLiquidations() {
  const alerts = [];
  try {
    // 通过价格剧烈变动推算爆仓
    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');
    for (const t of tickers) {
      const priceChange = Math.abs(parseFloat(t.priceChangePercent || 0));
      const vol = parseFloat(t.quoteVolume || 0);
      const sym = t.symbol;

      // 价格剧烈波动 + 高成交量 = 大概率有大量爆仓
      if (priceChange > 10 && vol > 100e6) {
        // 估算爆仓量（粗略：成交量 * 波动率 * 杠杆系数）
        const estimatedLiquidation = vol * (priceChange / 100) * 0.15;
        alerts.push({
          symbol: sym,
          type: 'ESTIMATED_LIQUIDATIONS',
          severity: estimatedLiquidation > 100e6 ? 'critical' : estimatedLiquidation > 50e6 ? 'high' : 'medium',
          priceChange: t.priceChangePercent + '%',
          volume24h: vol,
          volumeStr: fmtMoney(vol),
          estimatedLiquidation,
          estimatedStr: fmtMoney(estimatedLiquidation),
          interpretation: parseFloat(t.priceChangePercent) > 0 ? '空头被爆' : '多头被爆',
          time: new Date().toISOString(),
        });
      }
    }
  } catch (e) {
    console.error(`⚠️ 清算估算失败: ${e.message}`);
  }
  return alerts;
}

// ══════════════════════════════════════════
// 报告生成
// ══════════════════════════════════════════
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
    scanBinanceFutures(),
    scanDeribitOptions(),
    estimateLiquidations(),
  ]);

  const allAlerts = [...binanceAlerts, ...deribitAlerts, ...liquidationAlerts];
  const critical = allAlerts.filter(a => a.severity === 'critical');
  const high = allAlerts.filter(a => a.severity === 'high');

  console.log(`📊 扫描完成 | Binance: ${binanceAlerts.length} | Deribit: ${deribitAlerts.length} | 清算估算: ${liquidationAlerts.length}`);
  console.log(`   🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  // 按类型分组输出
  const fundingAlerts = allAlerts.filter(a => a.type.startsWith('FUNDING'));
  const volatilityAlerts = allAlerts.filter(a => a.type === 'EXTREME_VOLATILITY');
  const optionsAlerts = allAlerts.filter(a => a.type.startsWith('OPTIONS'));
  const liqAlerts = allAlerts.filter(a => a.type === 'ESTIMATED_LIQUIDATIONS');
  const oiAlerts = allAlerts.filter(a => a.type === 'OPEN_INTEREST');
  const ratioAlerts = allAlerts.filter(a => a.type === 'TOP_TRADER_RATIO');
  const volumeAlerts = allAlerts.filter(a => a.type === 'MEGA_VOLUME');

  const output = formatSection;
  const sections = [
    output('💰 资金费率异常', fundingAlerts),
    output('🔥 极端波动', volatilityAlerts),
    output('🐋 大额成交量', volumeAlerts),
    output('💥 预估爆仓', liqAlerts),
    output('📊 期权大额到期/交易', optionsAlerts),
    output('📈 持仓量数据', oiAlerts),
    output('🏦 大户多空比', ratioAlerts),
  ].filter(Boolean);

  if (sections.length) {
    for (const s of sections) console.log(s);
  } else {
    console.log('✅ 当前无重大衍生品异动，市场平稳。');
  }

  // 写入 JSON
  const jsonOutput = {
    scanTime: new Date().toISOString(),
    summary: {
      binanceAlerts: binanceAlerts.length,
      deribitAlerts: deribitAlerts.length,
      liquidationAlerts: liquidationAlerts.length,
      criticalCount: critical.length,
      highCount: high.length,
    },
    items: allAlerts,
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(jsonOutput, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
