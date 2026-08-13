import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { createDatabase } from './database.js';

// EARTH prototype server: commands mutate canonical state; clients only submit intent.
const PORT = Number(process.env.PORT || 8787);
const database = createDatabase();
const commandResults = new Map();
const eventSubscribers = new Set();
function publish(type, payload) { const message = `data: ${JSON.stringify({ type, gameDay: state.clock.day, payload })}\n\n`; for (const response of eventSubscribers) response.write(message); }
const state = {
  clock: { day: 184, minute: 462, realSecondsPerGameMinute: 1 },
  world: { health: 68, batch: 498 },
  humans: { amara: { id: 'H-0044', name: 'Amara Kline', credits: 18420, standing: 742, legacy: 31, ageYears: 31 } },
  life: { generation: 1, successor: null, estatePeriodDays: 30 },
  institutions: {
    ouc: { id: 'OUC-001', kind: 'OUC', name: 'Organization of United Corporations', treasury: 0 },
    corporation: { id: 'CORP-001', kind: 'CORPORATION', name: 'Helios Cooperative', members: 42, stability: 76 },
    city: { id: 'CITY-0084', kind: 'CITY', name: 'New Carthage', residents: 18, fiscalHealth: 82, capacity: { housing: 76, energy: 92, connectivity: 88, health: 64 } },
    business: { id: 'B-1048', kind: 'BUSINESS', name: 'Kline Works', ownerId: 'H-0044' }
  },
  resources: { material: 420, components: 86, energy: 92, compute: 64 },
  businesses: { klineWorks: { id: 'B-1048', name: 'Kline Works', policy: 'reliability', condition: 96, research: 72 } },
  market: {
    products: {
      material: { price: 32.4, supply: 1240, demand: 980 },
      components: { price: 118.7, supply: 186, demand: 276 },
      energy: { price: 0.84, supply: 920, demand: 850 },
      compute: { price: 2.16, supply: 4820, demand: 2910 }
    }, orders: [], lastSettlement: null
  },
  governance: { proposals: [{ id: '042', title: 'Components maintenance levy', status: 'open', levy: 0.02, votes: { support: 41, oppose: 17, uncast: 42 }, ballots: {} }] },
  technology: { research: { id: 'TECH-001', name: 'Adaptive Maintenance AI', progress: 72, budgetPerDay: 240 } },
  ledger: []
};

const money = n => Math.round(n * 100) / 100;
function appendLedger({ debit, credit, amount, reason, correlationId }) {
  if (amount <= 0) throw new Error('Ledger amount must be positive');
  const entry = { id: randomUUID(), gameDay: state.clock.day, debit, credit, amount: money(amount), currency: 'CREDIT', reason, correlationId };
  state.ledger.push(entry); if (database) void database.saveLedger(entry).catch(error => console.error('ledger persistence failed', error.message)); return entry;
}
function human(id = 'amara') { const value = state.humans[id]; if (!value) throw new Error('Human not found'); return value; }
function advanceDay() {
  state.clock.day += 1; state.clock.minute = 0;
  const player = human(); const business = state.businesses.klineWorks;
  const revenue = business.policy === 'margin' ? 690 : business.policy === 'capacity' ? 820 : 760;
  player.credits += revenue;
  appendLedger({ debit: 'market-buyers', credit: 'H-0044', amount: revenue, reason: 'business_output', correlationId: randomUUID() });
  business.condition = Math.max(0, business.condition - (business.policy === 'capacity' ? 3 : 1));
  state.resources.components = Math.max(0, state.resources.components - 12);
  state.resources.material += 24;
  state.resources.compute += 8;
  state.technology.research.progress = Math.min(100, state.technology.research.progress + 2);
  if (state.clock.day % 365 === 0) { player.ageYears += 1; player.legacy += 1; }
  state.world.batch = 86400;
  if (database) void Promise.all([database.saveWorld({ day: state.clock.day, minute: state.clock.minute, health: state.world.health, batch: state.world.batch }), database.saveBusiness(business), database.saveResources(state.resources), database.saveTechnology(state.technology.research)]).catch(error => console.error('day persistence failed', error.message));
  const result = { day: state.clock.day, revenue, condition: business.condition }; publish('world.day_advanced', result); return result;
}
function settleMarket() {
  const eligible = state.market.orders.filter(o => o.status === 'open');
  const fills = [];
  for (const product of Object.keys(state.market.products)) {
    const book = eligible.filter(o => o.product === product).sort((a, b) => a.createdAt - b.createdAt);
    const market = state.market.products[product];
    let supply = market.supply;
    for (const order of book) {
      if (supply <= 0) break;
      const fill = Math.min(order.quantity, supply);
      const price = money(Math.min(order.limitPrice, market.price));
      const total = money(fill * price);
      const buyer = human(order.humanId);
      if (buyer.credits < total) { order.status = 'rejected'; continue; }
      buyer.credits -= total; appendLedger({ debit: order.humanId, credit: 'central-market', amount: total, reason: 'market_order', correlationId: order.id });
      state.resources[product] += fill;
      order.filled = fill; order.status = fill === order.quantity ? 'filled' : 'partial'; supply -= fill; if (database) void database.saveOrder(order).catch(error => console.error('settlement persistence failed', error.message));
      fills.push({ orderId: order.id, product, quantity: fill, price, total });
    }
  }
  state.market.lastSettlement = { day: state.clock.day, fills };
  if (database) void database.saveResources(state.resources).catch(error => console.error('market inventory persistence failed', error.message));
  publish('market.batch_settled', state.market.lastSettlement);
  return state.market.lastSettlement;
}
function command(path, body) {
  if (path === '/api/world' && body.method === 'GET') return snapshot();
  if (path === '/api/storage' && body.method === 'GET') return { configured: Boolean(database), mode: database ? 'postgres-ready' : 'memory-fallback' };
  if (path === '/api/audit' && body.method === 'GET') return audit();
  if (path === '/api/institutions' && body.method === 'GET') return state.institutions;
  if (path === '/api/life/successor' && body.method === 'POST') {
    if (typeof body.name !== 'string' || body.name.trim().length < 2) throw new Error('Successor name is required');
    state.life.successor = { name: body.name.trim(), registeredOnDay: state.clock.day }; if (database) void database.saveSuccession(state.life.successor).catch(error => console.error('succession persistence failed', error.message)); return { ok: true, life: state.life, state: snapshot() };
  }
  const correlationId = body.correlationId;
  if (correlationId && commandResults.has(correlationId)) return commandResults.get(correlationId);
  if (path === '/api/day/advance' && body.method === 'POST') return { ok: true, result: advanceDay(), state: snapshot() };
  if (path === '/api/market/orders' && body.method === 'POST') {
    const product = state.market.products[body.product]; if (!product) throw new Error('Unknown product');
    if (!Number.isFinite(body.quantity) || body.quantity < 1 || !Number.isFinite(body.limitPrice) || body.limitPrice <= 0) throw new Error('Invalid order');
    const order = { id: randomUUID(), humanId: body.humanId || 'amara', product: body.product, quantity: Math.floor(body.quantity), limitPrice: Number(body.limitPrice), filled: 0, status: 'open', createdAt: Date.now() };
    state.market.orders.push(order); if (database) void database.saveOrder(order).catch(error => console.error('order persistence failed', error.message)); const result = { ok: true, order, state: snapshot() }; if (correlationId) commandResults.set(correlationId, result); return result;
  }
  if (path === '/api/market/settle' && body.method === 'POST') return { ok: true, result: settleMarket(), state: snapshot() };
  if (path === '/api/businesses/kline-works/policy' && body.method === 'POST') {
    if (!['reliability', 'margin', 'capacity'].includes(body.policy)) throw new Error('Unknown policy');
    state.businesses.klineWorks.policy = body.policy; if (database) void database.saveBusiness(state.businesses.klineWorks).catch(error => console.error('policy persistence failed', error.message)); publish('business.policy_changed', { businessId: 'B-1048', policy: body.policy }); return { ok: true, policy: body.policy, state: snapshot() };
  }
  if (path === '/api/research/fund' && body.method === 'POST') {
    const amount = Number(body.amount || 240); if (amount < 1) throw new Error('Invalid funding amount');
    const player = human(); if (player.credits < amount) throw new Error('Insufficient Credits');
    player.credits -= amount; state.technology.research.progress = Math.min(100, state.technology.research.progress + 4);
    appendLedger({ debit: 'H-0044', credit: 'research-project-TECH-001', amount, reason: 'research_funding', correlationId: randomUUID() }); if (database) void database.saveTechnology(state.technology.research).catch(error => console.error('research persistence failed', error.message));
    const result = { ok: true, research: state.technology.research, state: snapshot() }; publish('research.progressed', state.technology.research); if (correlationId) commandResults.set(correlationId, result); return result;
  }
  if (path === '/api/governance/proposals/042/vote' && body.method === 'POST') {
    if (!['support', 'oppose', 'abstain'].includes(body.vote)) throw new Error('Invalid ballot');
    const proposal = state.governance.proposals[0]; const humanId = body.humanId || 'amara';
    if (proposal.ballots[humanId]) throw new Error('Ballot already recorded');
    proposal.ballots[humanId] = body.vote; proposal.votes.uncast = Math.max(0, proposal.votes.uncast - 1); if (body.vote !== 'abstain') proposal.votes[body.vote] += 1; if (database) void database.saveBallot('042', humanId, body.vote).catch(error => console.error('ballot persistence failed', error.message)); publish('governance.vote_updated', { proposalId: '042', vote: body.vote, votes: proposal.votes });
    return { ok: true, proposal, state: snapshot() };
  }
  throw new Error('Route not found');
}
function snapshot() { return { clock: state.clock, world: state.world, human: human(), life: state.life, institutions: state.institutions, resources: state.resources, business: state.businesses.klineWorks, market: state.market, governance: state.governance, technology: state.technology, ledgerEntries: state.ledger.slice(-25) }; }
function audit() {
  const ordersValid = state.market.orders.every(order => order.filled >= 0 && order.filled <= order.quantity && ['open', 'partial', 'filled', 'rejected', 'cancelled'].includes(order.status));
  const ledgerValid = state.ledger.every(entry => entry.amount > 0 && entry.debit && entry.credit && entry.currency === 'CREDIT' && entry.debit !== entry.credit);
  const balancesValid = Object.values(state.humans).every(player => player.credits >= 0);
  const ballots = state.governance.proposals.flatMap(proposal => Object.keys(proposal.ballots));
  const ballotUniqueness = new Set(ballots).size === ballots.length;
  return { ok: ordersValid && ledgerValid && balancesValid && ballotUniqueness, checks: { ordersValid, ledgerValid, balancesValid, ballotUniqueness }, inspected: { orders: state.market.orders.length, ledgerEntries: state.ledger.length, humans: Object.keys(state.humans).length, ballots: ballots.length }, gameDay: state.clock.day };
}
function send(res, status, data) { res.writeHead(status, { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type' }); res.end(JSON.stringify(data)); }
async function serveStatic(res, pathname) {
  const files = { '/': resolve('index.html'), '/index.html': resolve('index.html'), '/landing.css': resolve('landing.css'), '/prototype3.html': resolve('../prototype3.html'), '/prototype3.css': resolve('../prototype3.css'), '/prototype3.js': resolve('../prototype3.js') };
  const file = files[pathname]; if (!file) return false;
  const content = await readFile(file); const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8' };
  res.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' }); res.end(content); return true;
}
async function hydrateFromDatabase() {
  if (!database) return;
  const canonical = await database.loadCanonical();
  if (canonical.world) { state.clock.day = Number(canonical.world.game_day); state.clock.minute = canonical.world.game_minute; state.world.health = canonical.world.health; state.world.batch = canonical.world.market_batch_seconds; }
  if (canonical.human) { state.humans.amara.name = canonical.human.display_name; state.humans.amara.standing = canonical.human.standing; state.humans.amara.legacy = canonical.human.legacy; }
  if (canonical.resources?.length) for (const resource of canonical.resources) state.resources[resource.resource] = Number(resource.amount);
  if (canonical.business) { state.businesses.klineWorks.name = canonical.business.name; state.businesses.klineWorks.policy = canonical.business.policy; state.businesses.klineWorks.condition = Number(canonical.business.condition); }
  if (canonical.technology) { state.technology.research.name = canonical.technology.name; state.technology.research.progress = Number(canonical.technology.progress); }
  if (canonical.orders) state.market.orders = canonical.orders.map(order => ({ id: order.id, humanId: 'amara', product: order.product, quantity: order.quantity, limitPrice: Number(order.limit_price), filled: order.filled_quantity, status: order.status, createdAt: Number(order.created_at) }));
  for (const ballot of canonical.ballots || []) state.governance.proposals[0].ballots.amara = ballot.choice;
}
const server = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return send(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host}`); let raw = ''; for await (const chunk of req) raw += chunk;
  if (req.method === 'GET' && url.pathname === '/api/events') { res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive', 'access-control-allow-origin': '*' }); res.write(`data: ${JSON.stringify({ type: 'connected', gameDay: state.clock.day })}\n\n`); eventSubscribers.add(res); req.on('close', () => eventSubscribers.delete(res)); return; }
  if (req.method === 'GET' && await serveStatic(res, url.pathname)) return;
  try { const result = command(url.pathname, { ...(raw ? JSON.parse(raw) : {}), method: req.method }); send(res, 200, result); }
  catch (error) { send(res, error.message === 'Route not found' ? 404 : 400, { ok: false, error: error.message }); }
});
hydrateFromDatabase().then(() => server.listen(PORT, () => console.log(`EARTH authoritative prototype server listening on http://localhost:${PORT}`))).catch(error => { console.error('database hydration failed', error.message); server.listen(PORT, () => console.log(`EARTH server running with fallback state on http://localhost:${PORT}`)); });
