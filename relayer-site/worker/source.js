import { ethers } from 'ethers';

const ABI = [
  'function openRound(uint256 id)',
  'function rounds(uint256 id) view returns (uint64 openedAt,uint64 closedAt,bool open)',
  'function joinFor(address player,uint256 roundId,uint8 strategy,uint256 deadline,bytes signature)',
  'function cashOutFor(address player,uint256 roundId,uint256 deadline,bytes signature)'
];
const requestLog = new Map();
const MAX_REQUESTS_PER_WINDOW = 12;
const WINDOW_MS = 60_000;
const cors = { 'access-control-allow-origin':'*', 'access-control-allow-headers':'content-type', 'access-control-allow-methods':'POST, OPTIONS' };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers:{...cors, 'content-type':'application/json'} });
async function liveRound(env) {
  const response = await fetch('https://api.squeekchain.com/v1/status');
  if (!response.ok) throw new Error('telemetry_unavailable');
  const data = await response.json();
  const measurement = data.measurement || {};
  const observedAt = Date.parse(measurement.observedAt || data.generatedAt || '');
  const staleAfter = Number(measurement.staleAfterSeconds || 120) * 1000;
  const fresh = measurement.freshness === 'online' && Number.isFinite(observedAt) && Date.now() - observedAt <= staleAfter;
  const rpm = Number(measurement.rpmMilli || 0);
  const speed = Number(measurement.speedMmPerSecond || 0);
  const state = String(measurement.coreStatus || '').toUpperCase();
  const running = fresh && (state === 'RUNNING' || state === 'ACTIVE' || rpm > 0 || speed > 0);
  const lastRound = Number(data.oracle?.latestClosure?.lastRound || data.builder?.anchor?.settledThroughRound || 0);
  return {running, nextRound:lastRound + 1};
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, {status:204, headers:cors});
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') return json({ok:true, chain:'sepolia', contract:env.RELAY_CONTRACT});
    if (request.method !== 'POST' || !['/join','/cashout'].includes(url.pathname)) return json({error:'not_found'}, 404);
    try {
      const ip = request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
      const now = Date.now();
      const recent = (requestLog.get(ip) || []).filter((timestamp) => now - timestamp < WINDOW_MS);
      if (recent.length >= MAX_REQUESTS_PER_WINDOW) return json({error:'rate_limited'}, 429);
      recent.push(now); requestLog.set(ip, recent);
      const body = await request.json();
      if (!/^0x[a-fA-F0-9]{40}$/.test(body.player) || !/^[0-9]+$/.test(String(body.roundId)) || !body.deadline || !/^0x[a-fA-F0-9]{130}$/.test(body.signature)) return json({error:'invalid_intent_fields'}, 400);
      if (Number(body.deadline) < Math.floor(Date.now()/1000)) return json({error:'intent_expired'}, 400);
      if (Number(body.deadline) > Math.floor(Date.now()/1000) + 300) return json({error:'deadline_too_far'}, 400);
      const provider = new ethers.JsonRpcProvider(env.SEPOLIA_RPC_URL);
      const signer = new ethers.Wallet(env.KEEPER_PRIVATE_KEY, provider);
      const relay = new ethers.Contract(env.RELAY_CONTRACT, ABI, signer);
      if (url.pathname === '/join') {
        const live = await liveRound(env);
        if (!live.running) return json({error:'wheel_not_running'}, 409);
        if (Number(body.roundId) !== live.nextRound) return json({error:'round_not_current', expectedRound:String(live.nextRound)}, 409);
        const round = await relay.rounds(body.roundId);
        if (!round.open) {
          try { await (await relay.openRound(body.roundId)).wait(); } catch (error) {
            const retry = await relay.rounds(body.roundId);
            if (!retry.open) throw error;
          }
        }
      }
      const tx = url.pathname === '/join'
        ? await relay.joinFor(body.player, body.roundId, body.strategy, body.deadline, body.signature)
        : await relay.cashOutFor(body.player, body.roundId, body.deadline, body.signature);
      const receipt = await tx.wait();
      return json({ok:true, transactionHash:receipt.hash, blockNumber:receipt.blockNumber});
    } catch (error) {
      return json({error: error.shortMessage || error.message || 'relay_failed'}, 400);
    }
  }
};
