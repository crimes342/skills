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
