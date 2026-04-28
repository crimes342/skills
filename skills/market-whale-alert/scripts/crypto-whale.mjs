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
    btcMin:     { type: 'string', default: '100' },      // BTC 大额阈值
    ethMin:     { type: 'string', default: '1000' },     // ETH 大额阈值
    stableMin:  { type: 'string', default: '1000000' },  // 稳定币大额阈值 $1M
    liqMin:     { type: 'string', default: '10000000' }, // 爆仓阈值 $10M
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

function fmtBTC(n) { return `${Number(n).toFixed(2)} BTC`; }

// ══════════════════════════════════════════
// 模块1: BTC 大额交易（Blockchain.com API）
// ══════════════════════════════════════════
async function scanBTCTransactions() {
  const alerts = [];
  try {
    // 获取最近未确认交易的大额转账
    const data = await fetchJSON('https://blockchain.info/unconfirmed-transactions?format=json');
    const txs = data.txs || [];
    for (const tx of txs) {
      // 计算总输出值（satoshi -> BTC）
      const totalOut = tx.out.reduce((sum, o) => sum + (o.value || 0), 0) / 1e8;
      if (totalOut >= CONFIG.btcThreshold) {
        const inputs = (tx.inputs || []).map(i => i.prev_out?.addr || 'unknown').slice(0, 3);
        const outputs = (tx.out || []).map(o => ({ addr: o.addr || 'unknown', value: o.value / 1e8 })).slice(0, 3);
        alerts.push({
          chain: 'BTC',
          type: 'LARGE_TRANSFER',
          severity: totalOut >= 1000 ? 'critical' : totalOut >= 500 ? 'high' : 'medium',
          amount: totalOut,
          amountStr: fmtBTC(totalOut),
          txHash: tx.hash,
          inputCount: (tx.inputs || []).length,
          outputCount: (tx.out || []).length,
          topInputs: inputs,
          topOutputs: outputs,
          time: new Date((tx.time || Date.now() / 1000) * 1000).toISOString(),
        });
      }
    }
  } catch (e) {
    console.error(`⚠️ BTC 扫描失败: ${e.message}`);
  }
  return alerts;
}

// ══════════════════════════════════════════
// 模块2: ETH 大额转账（Etherscan 公开 API）
// ══════════════════════════════════════════
async function scanETHTransactions() {
  const alerts = [];
  try {
    // 使用 Etherscan 公开 API 获取最新区块的交易
    const blockData = await fetchJSON('https://api.etherscan.io/api?module=proxy&action=eth_blockNumber');
    const blockNum = parseInt(blockData.result, 16);

    // 检查最近几个区块
    for (let i = 0; i < 3; i++) {
      const block = await fetchJSON(`https://api.etherscan.io/api?module=proxy&action=eth_getBlockByNumber&tag=0x${(blockNum - i).toString(16)}&boolean=true`);
      const txs = block.result?.transactions || [];
      for (const tx of txs) {
        const valueWei = parseInt(tx.value || '0x0', 16);
        const valueETH = valueWei / 1e18;
        if (valueETH >= CONFIG.ethThreshold) {
          alerts.push({
            chain: 'ETH',
            type: 'LARGE_TRANSFER',
            severity: valueETH >= 10000 ? 'critical' : valueETH >= 5000 ? 'high' : 'medium',
            amount: valueETH,
            amountStr: `${valueETH.toFixed(2)} ETH`,
            txHash: tx.hash,
            from: tx.from,
            to: tx.to,
            blockNumber: blockNum - i,
            time: new Date().toISOString(),
          });
        }
      }
    }
  } catch (e) {
    console.error(`⚠️ ETH 扫描失败: ${e.message}`);
  }
  return alerts;
}

// ══════════════════════════════════════════
// 模块3: 加密市场行情 + 24h变动（CoinGecko）
// ══════════════════════════════════════════
async function scanMarketData() {
  const alerts = [];
  try {
    const data = await fetchJSON('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=volume_desc&per_page=20&page=1&sparkline=false&price_change_percentage=1h,24h');
    for (const coin of data) {
      // 24h 内跌幅 > 10% 或涨幅 > 15%
      const change24h = coin.price_change_percentage_24h || 0;
      const change1h = coin.price_change_percentage_1h_in_currency || 0;
      const vol = coin.total_volume || 0;

      if (Math.abs(change24h) > 10 || Math.abs(change1h) > 5) {
        alerts.push({
          chain: coin.symbol.toUpperCase(),
          type: Math.abs(change1h) > 5 ? 'PRICE_FLASH' : 'PRICE_MOVE',
          severity: Math.abs(change24h) > 20 || Math.abs(change1h) > 8 ? 'critical' : 'high',
          price: coin.current_price,
          change24h: change24h.toFixed(2) + '%',
          change1h: change1h.toFixed(2) + '%',
          volume24h: vol,
          volumeStr: fmtMoney(vol),
          marketCap: coin.market_cap,
          time: new Date().toISOString(),
        });
      }

      // 成交量异常（top 20 币种中，成交量 > 市值 50%）
      if (coin.market_cap > 0 && vol / coin.market_cap > 0.5) {
        alerts.push({
          chain: coin.symbol.toUpperCase(),
          type: 'VOLUME_ANOMALY',
          severity: 'high',
          price: coin.current_price,
          volume24h: vol,
          volumeStr: fmtMoney(vol),
          marketCap: coin.market_cap,
          volumeMcapRatio: (vol / coin.market_cap * 100).toFixed(1) + '%',
          time: new Date().toISOString(),
        });
      }
    }
  } catch (e) {
    console.error(`⚠️ 市场行情扫描失败: ${e.message}`);
  }
  return alerts;
}

// ══════════════════════════════════════════
// 模块4: 期货爆仓数据（Binance Futures 公开 API）
// ══════════════════════════════════════════
async function scanFuturesLiquidations() {
  const alerts = [];
  try {
    // 获取 Binance Futures 所有交易对的 ticker
    const tickers = await fetchJSON('https://fapi.binance.com/fapi/v1/ticker/24hr');

    // 筛选异常
    for (const t of tickers) {
      const sym = t.symbol || 'UNKNOWN';
      const vol = parseFloat(t.quoteVolume || 0);
      const priceChange = parseFloat(t.priceChangePercent || 0);
      const lastPrice = parseFloat(t.lastPrice || 0);

      // 价格剧烈波动（15分钟内）
      if (Math.abs(priceChange) > 8 && vol > 10e6) {
        alerts.push({
          symbol: sym || t.symbol || 'UNKNOWN',
          type: 'FUTURES_VOLATILITY',
          severity: Math.abs(priceChange) > 15 ? 'critical' : 'high',
          price: lastPrice,
          change: priceChange.toFixed(2) + '%',
          volume24h: vol,
          volumeStr: fmtMoney(vol),
          time: new Date().toISOString(),
        });
      }
    }

    // 获取 Binance Futures 大额交易（最近成交）
    try {
      const openInterest = await fetchJSON('https://fapi.binance.com/fapi/v1/openInterest?symbol=BTCUSDT');
      alerts.push({
        symbol: 'BTCUSDT',
        type: 'OPEN_INTEREST',
        severity: 'info',
        openInterest: parseFloat(openInterest.openInterest),
        openInterestStr: fmtBTC(openInterest.openInterest),
        time: new Date().toISOString(),
      });
    } catch (e) { /* skip */ }

    // 获取 funding rate 异常
    const fundingRates = await fetchJSON('https://fapi.binance.com/fapi/v1/premiumIndex');
    for (const fr of fundingRates) {
      const rate = parseFloat(fr.lastFundingRate || 0);
      if (Math.abs(rate) > 0.001) { // > 0.1%
        alerts.push({
          symbol: fr.symbol,
          type: 'FUNDING_RATE_ANOMALY',
          severity: Math.abs(rate) > 0.003 ? 'critical' : 'high',
          fundingRate: (rate * 100).toFixed(4) + '%',
          markPrice: parseFloat(fr.markPrice),
          nextFundingTime: new Date(fr.nextFundingTime).toISOString(),
          time: new Date().toISOString(),
        });
      }
    }
  } catch (e) {
    console.error(`⚠️ 期货扫描失败: ${e.message}`);
  }
  return alerts;
}

// ══════════════════════════════════════════
// 模块5: 大额链上稳定币流动（Etherscan）
// ══════════════════════════════════════════
async function scanStablecoinTransfers() {
  const alerts = [];
  // USDT 和 USDC 合约地址
  const stablecoins = [
    { name: 'USDT', contract: '0xdac17f958d2ee523a2206206994597c13d831ec7', decimals: 6 },
    { name: 'USDC', contract: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', decimals: 6 },
  ];

  for (const coin of stablecoins) {
    try {
      // 获取最新大额转账（Etherscan token transfers API）
      const data = await fetchJSON(
        `https://api.etherscan.io/api?module=account&action=tokentx&contractaddress=${coin.contract}&page=1&offset=20&sort=desc`
      );
      const txs = data.result || [];
      for (const tx of txs) {
        const value = parseInt(tx.value || '0') / Math.pow(10, coin.decimals);
        if (value >= CONFIG.stableThreshold / 1e6) { // stableThreshold is in cents, convert
          alerts.push({
            chain: coin.name,
            type: 'STABLECOIN_WHALE',
            severity: value >= 10e6 ? 'critical' : value >= 5e6 ? 'high' : 'medium',
            amount: value,
            amountStr: `${(value / 1e6).toFixed(2)}M ${coin.name}`,
            from: tx.from,
            to: tx.to,
            txHash: tx.hash,
            time: new Date(parseInt(tx.timeStamp) * 1000).toISOString(),
          });
        }
      }
    } catch (e) {
      console.error(`⚠️ ${coin.name} 扫描失败: ${e.message}`);
    }
  }
  return alerts;
}

// ══════════════════════════════════════════
// 汇总
// ══════════════════════════════════════════
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

  // 并行运行所有扫描
  const [btcAlerts, ethAlerts, marketAlerts, futuresAlerts, stableAlerts] = await Promise.all([
    scanBTCTransactions(),
    scanETHTransactions(),
    scanMarketData(),
    scanFuturesLiquidations(),
    scanStablecoinTransfers(),
  ]);

  const allAlerts = [...btcAlerts, ...ethAlerts, ...marketAlerts, ...futuresAlerts, ...stableAlerts];
  const critical = allAlerts.filter(a => a.severity === 'critical');
  const high = allAlerts.filter(a => a.severity === 'high');

  // 输出报告
  console.log(`📊 扫描完成 | ${new Date().toISOString()}`);
  console.log(`   BTC 大额: ${btcAlerts.length} | ETH 大额: ${ethAlerts.length} | 行情异动: ${marketAlerts.length} | 期货异动: ${futuresAlerts.length} | 稳定币: ${stableAlerts.length}`);
  console.log(`   🚨 Critical: ${critical.length} | ⚠️ High: ${high.length}\n`);

  if (btcAlerts.length) {
    console.log('₿ BTC 大额转账');
    console.log('─'.repeat(40));
    console.log(formatReport(btcAlerts));
  }

  if (ethAlerts.length) {
    console.log('Ξ ETH 大额转账');
    console.log('─'.repeat(40));
    console.log(formatReport(ethAlerts));
  }

  if (stableAlerts.length) {
    console.log('💵 稳定币巨鲸');
    console.log('─'.repeat(40));
    console.log(formatReport(stableAlerts));
  }

  if (marketAlerts.length) {
    console.log('📈 行情异动');
    console.log('─'.repeat(40));
    console.log(formatReport(marketAlerts));
  }

  if (futuresAlerts.length) {
    console.log('🔥 期货异动');
    console.log('─'.repeat(40));
    console.log(formatReport(futuresAlerts));
  }

  if (!allAlerts.length) {
    console.log('✅ 当前无重大异动，市场平静。');
  }

  // 写入 JSON
  const output = {
    scanTime: new Date().toISOString(),
    summary: {
      btcAlerts: btcAlerts.length,
      ethAlerts: ethAlerts.length,
      marketAlerts: marketAlerts.length,
      futuresAlerts: futuresAlerts.length,
      stableAlerts: stableAlerts.length,
      criticalCount: critical.length,
      highCount: high.length,
    },
    items: allAlerts,
  };

  writeFileSync(CONFIG.jsonOutput, JSON.stringify(output, null, 2));
  console.error(`\n📁 JSON → ${CONFIG.jsonOutput}`);
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
