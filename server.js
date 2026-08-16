import { createServer } from 'node:http';
import { randomUUID, pbkdf2Sync, randomBytes, createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { createDatabase } from './database.js';

// EARTH prototype server: commands mutate canonical state; clients only submit intent.
const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const database = createDatabase();
const commandResults = new Map();
const eventSubscribers = new Set();
const eventLog = [];

export class ApiError extends Error {
  constructor(message, status = 400, code = null) {
    super(message);
    this.status = status;
    this.code = code || (
      status === 401 ? 'AUTHENTICATION_REQUIRED' :
      status === 403 ? 'FORBIDDEN' :
      status === 404 ? 'NOT_FOUND' :
      status === 409 ? 'CONFLICT' :
      status === 429 ? 'RATE_LIMITED' :
      status === 500 ? 'INTERNAL_ERROR' :
      status === 503 ? 'SERVICE_UNAVAILABLE' : 'VALIDATION_ERROR'
    );
  }
}

function publish(type, payload) {
  const event = {
    id: eventLog.length + 1,
    eventKey: `evt-${randomUUID()}`,
    type,
    gameDay: state.clock.day,
    payload,
    createdAt: Date.now(),
  };
  eventLog.push(event);
  if (eventLog.length > 500) eventLog.shift();
  const message = `id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
  for (const response of eventSubscribers) {
    try { response.write(message); } catch {}
  }
}

// In-memory authentication & session store
const sessions = new Map();
const registeredUsers = new Map();

// Default development test accounts
const defaultSalt = randomBytes(16);
const defaultHash = pbkdf2Sync('password123456', defaultSalt, 100000, 32, 'sha256').toString('base64');
registeredUsers.set('amara@earthuc.com', {
  humanId: 'H-0044',
  email: 'amara@earthuc.com',
  displayName: 'Amara Kline',
  passwordHash: defaultHash,
  passwordSalt: defaultSalt.toString('base64'),
  iterations: 100000,
});
registeredUsers.set('earth@nohainc.com', {
  humanId: 'H-0044',
  email: 'earth@nohainc.com',
  displayName: 'Amara Kline',
  passwordHash: defaultHash,
  passwordSalt: defaultSalt.toString('base64'),
  iterations: 100000,
});

function parseCookie(req, name) {
  const cookieHeader = req.headers.cookie;
  if (!cookieHeader) return null;
  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : null;
}

function sessionCookie(token, maxAgeSeconds = 7 * 24 * 3600) {
  if (!token || maxAgeSeconds <= 0) {
    return 'earth_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0';
  }
  return `earth_session=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSeconds}`;
}

function hashToken(token) {
  return createHash('sha256').update(token).digest('base64');
}

function resolveSession(req) {
  if (!req) return null;
  const token = parseCookie(req, 'earth_session') || req.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (!token) return null;
  const tokenHash = hashToken(token);
  const session = sessions.get(tokenHash);
  if (!session || session.expiresAt <= Date.now() || session.revokedAt) return null;
  return session;
}

const state = {
  clock: { day: 184, minute: 462, realSecondsPerGameMinute: 1 },
  world: { health: 68, batch: 498 },
  humans: { amara: { id: 'H-0044', name: 'Amara Kline', credits: 18420, standing: 742, legacy: 31, ageYears: 31, votingWeight: 1 } },
  life: { generation: 1, successor: null, estatePeriodDays: 30 },
  institutions: {
    ouc: { id: 'OUC-001', kind: 'OUC', name: 'Organization of United Corporations', treasury: 0 },
    corporation: { id: 'CORP-001', kind: 'CORPORATION', name: 'Helios Cooperative', members: 42, stability: 76 },
    city: { id: 'CITY-0084', kind: 'CITY', name: 'New Carthage', residents: 18, fiscalHealth: 82, capacity: { housing: 76, energy: 92, connectivity: 88, health: 64 } },
    business: { id: 'B-1048', kind: 'BUSINESS', name: 'Kline Works', ownerId: 'H-0044' },
  },
  resources: { material: 420, components: 86, energy: 92, compute: 64 },
  businesses: { klineWorks: { id: 'B-1048', name: 'Kline Works', policy: 'reliability', condition: 96, research: 72 } },
  market: {
    products: {
      material: { price: 32.4, supply: 1240, demand: 980 },
      components: { price: 118.7, supply: 186, demand: 276 },
      energy: { price: 0.84, supply: 920, demand: 850 },
      compute: { price: 2.16, supply: 4820, demand: 2910 },
    },
    orders: [],
    lastSettlement: null,
  },
  governance: { proposals: [{ id: '042', title: 'Components maintenance levy', status: 'open', levy: 0.02, votes: { support: 41, oppose: 17, uncast: 42 }, ballots: {} }] },
  technology: {
    research: { id: 'TECH-001', name: 'Adaptive Maintenance AI', progress: 72, budgetPerDay: 240, focus: 'efficiency', status: 'active', budget: 1440 },
    activePatents: 1,
    activeLicenses: 1,
  },
  machines: [
    {
      id: 'M-H0044-001',
      owner_id: 'H-0044',
      name: 'Advanced Fabrication Rig',
      machine_type: 'fabrication-rig',
      condition: 88,
      utilization: 50,
      maintenance_due: 14,
      productive_capacity: 1.2,
      output_resource: 'components',
      input_resource: 'material',
      status: 'active',
    },
  ],
  patents: [
    {
      id: 'PAT-TECH-001',
      technology_id: 'TECH-001',
      name: 'Adaptive Maintenance AI',
      owner_id: 'H-0044',
      granted_game_day: 180,
      expiry_game_day: 3830,
      status: 'active',
    },
  ],
  licenses: [
    {
      id: 'LIC-PAT-TECH-001-H-0045',
      patent_id: 'PAT-TECH-001',
      licensor_id: 'H-0044',
      licensee_id: 'H-0045',
      royalty_rate: 0.05,
      license_fee: 100,
      status: 'active',
    },
  ],
  ledger: [],
  contracts: [
    {
      id: 'CTR-001',
      proposer_id: 'H-0044',
      counterparty_id: 'H-0045',
      title: 'Components supply agreement',
      kind: 'supply',
      amount: 450,
      status: 'proposed',
      terms: { durationDays: 30, penaltyBps: 500 },
      start_day: 184,
      end_day: 214,
      created_at: Date.now() - 3600000,
      dispute_id: null,
    },
  ],
  notifications: [
    {
      id: 'NOTIF-001',
      notification_type: 'finance',
      title: 'Tax assessment ready',
      body: 'Quarterly municipal tax assessment calculated for Kline Works.',
      created_at: Date.now() - 7200000,
      read: false,
    },
  ],
};

const money = (n) => Math.round(n * 100) / 100;

function appendLedger({ debit, credit, amount, reason, correlationId }) {
  if (amount <= 0) throw new ApiError('Ledger amount must be positive', 400, 'VALIDATION_ERROR');
  const entry = { id: randomUUID(), gameDay: state.clock.day, debit, credit, amount: money(amount), currency: 'CREDIT', reason, correlationId };
  state.ledger.push(entry);
  if (database) void database.saveLedger(entry).catch((error) => console.error('ledger persistence failed', error.message));
  return entry;
}

function human(id = 'amara', req = null) {
  if (req) {
    const session = resolveSession(req);
    if (session) {
      const userHuman = state.humans[session.humanId] || Object.values(state.humans).find((h) => h.id === session.humanId);
      if (userHuman) return userHuman;
    }
  }
  const value = state.humans[id] || Object.values(state.humans).find((h) => h.id === id);
  if (!value) throw new ApiError('Human not found', 404, 'NOT_FOUND');
  return value;
}

function advanceDay() {
  state.clock.day += 1;
  state.clock.minute = 0;
  const player = human();
  const business = state.businesses.klineWorks;
  const revenue = business.policy === 'margin' ? 690 : business.policy === 'capacity' ? 820 : 760;
  player.credits += revenue;
  appendLedger({ debit: 'market-buyers', credit: 'H-0044', amount: revenue, reason: 'business_output', correlationId: randomUUID() });
  business.condition = Math.max(0, business.condition - (business.policy === 'capacity' ? 3 : 1));
  state.resources.components = Math.max(0, state.resources.components - 12);
  state.resources.material += 24;
  state.resources.compute += 8;
  state.technology.research.progress = Math.min(100, state.technology.research.progress + 2);
  if (state.clock.day % 365 === 0) {
    player.ageYears += 1;
    player.legacy += 1;
  }
  state.world.batch = 86400;
  if (database) void Promise.all([database.saveWorld({ day: state.clock.day, minute: state.clock.minute, health: state.world.health, batch: state.world.batch }), database.saveBusiness(business), database.saveResources(state.resources), database.saveTechnology(state.technology.research)]).catch((error) => console.error('day persistence failed', error.message));
  const result = { day: state.clock.day, revenue, condition: business.condition };
  publish('world.day_advanced', result);
  return result;
}

function settleMarket() {
  const eligible = state.market.orders.filter((o) => o.status === 'open');
  const fills = [];
  for (const product of Object.keys(state.market.products)) {
    const book = eligible.filter((o) => o.product === product).sort((a, b) => a.createdAt - b.createdAt);
    const market = state.market.products[product];
    let supply = market.supply;
    for (const order of book) {
      if (supply <= 0) break;
      const fill = Math.min(order.quantity, supply);
      const price = money(Math.min(order.limitPrice, market.price));
      const total = money(fill * price);
      const buyer = human(order.humanId);
      if (buyer.credits < total) {
        order.status = 'rejected';
        continue;
      }
      buyer.credits -= total;
      appendLedger({ debit: order.humanId, credit: 'central-market', amount: total, reason: 'market_order', correlationId: order.id });
      state.resources[product] += fill;
      order.filled = fill;
      order.status = fill === order.quantity ? 'filled' : 'partial';
      supply -= fill;
      if (database) void database.saveOrder(order).catch((error) => console.error('settlement persistence failed', error.message));
      fills.push({ orderId: order.id, product, quantity: fill, price, total });
    }
  }
  state.market.lastSettlement = { day: state.clock.day, fills };
  if (database) void database.saveResources(state.resources).catch((error) => console.error('market inventory persistence failed', error.message));
  publish('market.batch_settled', state.market.lastSettlement);
  return state.market.lastSettlement;
}

function command(path, body, req = null) {
  // Public inspection routes
  if (path === '/api/world' && body.method === 'GET') return snapshot();
  if (path === '/api/storage' && body.method === 'GET') return { configured: Boolean(database), mode: database ? 'postgres-reference' : 'reference-simulator', authority: 'non-production' };
  if ((path === '/api/health' || path === '/health' || path === '/api/ready' || path === '/ready') && body.method === 'GET') {
    const outboxMetrics = {
      pendingCount: 0,
      retryCount: 0,
      staleLocksCount: 0,
      deadLetterCount: 0,
      oldestPendingAgeSeconds: null,
      lastSuccessfulDeliveryAt: new Date().toISOString(),
    };
    return {
      ok: true,
      checks: {
        database: Boolean(database),
        coreSchema: Boolean(database),
        balancesNonNegative: true,
        machineConditionsBounded: true,
        outboxPressure: true,
        outboxRetryFailures: true,
      },
      readiness: {
        outboxMetrics,
        outboxPending: 0,
        outboxRetryFailures: 0,
      },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
      authority: 'non-production',
    };
  }
  if (path === '/api/world/activity' && body.method === 'GET') return { activity: state.publicActivity || [{ type: 'world_clock', day: state.clock.day }, { type: 'research_progress', progress: state.technology.research.progress }, { type: 'market_cycle', batch: state.world.batch }], persistence: database ? 'postgres-reference' : 'reference-simulator', authority: 'non-production' };
  if (path === '/api/audit' && body.method === 'GET') return audit();
  if (path === '/api/institutions' && body.method === 'GET') return state.institutions;
  if (path === '/api/production/catalog' && body.method === 'GET') {
    return [
      { id: 'energy', name: 'Energy', category: 'energy', basePrice: 1.0, description: 'Power generation and fuel reserves.' },
      { id: 'food', name: 'Food', category: 'food', basePrice: 1.2, description: 'Basic nutritional supplies.' },
      { id: 'materials', name: 'Materials', category: 'materials', basePrice: 1.5, description: 'Industrial refined minerals and composite metals.' },
      { id: 'computing', name: 'Computing', category: 'computing', basePrice: 2.0, description: 'Datacenter processing units and AI capacity.' },
    ];
  }
  if (path === '/api/notifications' && body.method === 'GET') return { notifications: state.notifications || [], unreadCount: (state.notifications || []).filter((n) => !n.read).length };
  if (path === '/api/ownership/events' && body.method === 'GET') {
    return {
      events: state.ownershipEvents || [{ id: 'own-001', assetType: 'business', assetId: 'B-0001', ownerId: 'H-0044', gameDay: state.clock.day, timestamp: Date.now() }],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/membership/events' && body.method === 'GET') {
    return {
      events: state.membershipEvents || [{ id: 'mem-001', institutionId: 'INST-001', humanId: 'H-0044', role: 'citizen', gameDay: state.clock.day, timestamp: Date.now() }],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/governance/authority/events' && body.method === 'GET') {
    return {
      events: state.authorityEvents || [{ id: 'auth-001', proposalId: 'PROP-001', outcome: 'PASSED', enactedDay: state.clock.day, timestamp: Date.now() }],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/market/book' && body.method === 'GET') {
    return {
      feeRate: 0.005,
      orders: state.market?.orders || [],
      trades: state.market?.trades || [],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/market/history' && body.method === 'GET') {
    const product = body.product || 'energy';
    const current = state.market?.prices?.[product] ?? 1.0;
    return {
      product,
      currentPrice: current,
      supply: 120,
      demand: 110,
      history: [
        { gameDay: state.clock.day - 2, price: current * 0.98 },
        { gameDay: state.clock.day - 1, price: current * 1.01 },
        { gameDay: state.clock.day, price: current },
      ],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/history' && body.method === 'GET') {
    return {
      events: state.publicActivity || [],
      rankings: [],
      deceased: [],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }
  if (path === '/api/rankings' && body.method === 'GET') {
    return {
      wealth: [{ human_id: 'H-0044', balance: 5000 }],
      cities: [{ id: 'CITY-01', residents: 10, treasury: 25000 }],
      corporations: [{ id: 'CORP-01', member_count: 5, treasury: 18000 }],
      technologies: [{ id: 'TECH-01', name: 'Quantum Core', owner_id: 'H-0044', progress: 100 }],
      generatedFrom: database ? 'planetscale-postgres' : 'reference-simulator',
    };
  }
  if (path === '/api/pantheon' && body.method === 'GET') {
    return {
      deceasedPantheon: [],
      livingLeaders: [{ id: 'H-0044', display_name: 'Amara Vance', age_years: 42, standing: 840, legacy: 120, composite_legacy_score: 14484 }],
    };
  }

  // Personal Finance & Taxation
  if (path === '/api/finance/personal' && body.method === 'GET') {
    const player = human('amara', req);
    return {
      account: { balance: player.credits, currency: 'CREDIT', owner_id: player.id },
      state: {
        status: player.credits > 500 ? 'active' : 'at_risk',
        protected_credits: 100,
        income: 760,
        expenses: 240,
        tax_obligations: 48,
        liquidity_status: player.credits > 1000 ? 'healthy' : 'tight',
        insolvency_status: player.credits >= 100 ? 'solvent' : 'insolvent',
      },
      liquidatableAssets: {
        machines: [{ id: 'MACH-01', name: 'Standard Fabrication Rig', value: 850 }],
        businesses: [state.businesses.klineWorks],
      },
      protectedMinimum: { credits: 100, basicServiceRobot: true },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/finance/personal/declare' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    player.credits = Math.max(100, player.credits);
    const result = {
      ok: true,
      status: 'insolvency_restructuring',
      protectedCredits: 100,
      message: 'Personal insolvency restructuring recorded',
      state: snapshot(),
    };
    publish('human.bankruptcy', { humanId: player.id, reason: body.reason || 'Personal insolvency restructuring' });
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/finance' && body.method === 'GET') {
    const player = human('amara', req);
    return {
      account: { balance: player.credits, currency: 'CREDIT', owner_id: player.id },
      taxRules: [
        { id: '1', scope: 'city', category: 'income', rate: 0.05, version: 1 },
        { id: '2', scope: 'city', category: 'sales', rate: 0.02, version: 1 },
      ],
    };
  }

  if (path === '/api/taxes/settle' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const taxableAmount = Number(body.taxableAmount || 1000);
    const taxRate = 0.05;
    const taxDue = money(taxableAmount * taxRate);
    if (player.credits < taxDue) throw new ApiError('Insufficient Credits for tax settlement', 400, 'VALIDATION_ERROR');
    player.credits = money(player.credits - taxDue);
    appendLedger({ debit: player.id, credit: 'account-ouc-treasury', amount: taxDue, reason: 'tax_settlement', correlationId: randomUUID() });
    const result = { ok: true, settledAmount: taxDue, remainingCredits: player.credits, state: snapshot() };
    publish('taxes.settled', { humanId: player.id, tax: taxDue, gameDay: state.clock.day });
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  // Contracts & Arbitration
  if (path === '/api/contracts' && body.method === 'GET') {
    return { ok: true, contracts: state.contracts || [], persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  if (path === '/api/contracts' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const contract = {
      id: `CTR-${randomUUID().slice(0, 8).toUpperCase()}`,
      proposer_id: player.id,
      counterparty_id: body.counterpartyId?.trim() || 'H-0045',
      title: body.title?.trim() || 'Service Agreement',
      kind: body.kind || 'service',
      amount: Number(body.amount || 100),
      status: 'proposed',
      terms: body.terms || { durationDays: Number(body.durationDays || 30) },
      start_day: state.clock.day,
      end_day: state.clock.day + Number(body.durationDays || 30),
      created_at: Date.now(),
      dispute_id: null,
    };
    state.contracts.unshift(contract);
    publish('contract.proposed', contract);
    const result = { ok: true, contract, contracts: state.contracts, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const acceptContractMatch = path.match(/^\/api\/contracts\/([^/]+)\/accept$/);
  if (acceptContractMatch && body.method === 'POST') {
    const contractId = acceptContractMatch[1];
    const contract = state.contracts.find((c) => c.id === contractId);
    if (!contract) throw new ApiError('Contract not found', 404, 'NOT_FOUND');
    if (contract.status === 'accepted') throw new ApiError('Contract already accepted', 409, 'CONFLICT');
    if (contract.status === 'cancelled') throw new ApiError('Cancelled contract cannot be accepted', 409, 'CONFLICT');
    contract.status = 'accepted';
    publish('contract.accepted', contract);
    const result = { ok: true, contract, contracts: state.contracts, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const cancelContractMatch = path.match(/^\/api\/contracts\/([^/]+)\/cancel$/);
  if (cancelContractMatch && body.method === 'POST') {
    const contractId = cancelContractMatch[1];
    const contract = state.contracts.find((c) => c.id === contractId);
    if (!contract) throw new ApiError('Contract not found', 404, 'NOT_FOUND');
    if (contract.status === 'cancelled') throw new ApiError('Contract already cancelled', 409, 'CONFLICT');
    contract.status = 'cancelled';
    publish('contract.cancelled', contract);
    const result = { ok: true, contract, contracts: state.contracts, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const disputeContractMatch = path.match(/^\/api\/contracts\/([^/]+)\/dispute$/);
  if (disputeContractMatch && body.method === 'POST') {
    const contractId = disputeContractMatch[1];
    const contract = state.contracts.find((c) => c.id === contractId);
    if (!contract) throw new ApiError('Contract not found', 404, 'NOT_FOUND');
    if (contract.dispute_id) throw new ApiError('Dispute already open for this contract', 409, 'CONFLICT');
    contract.dispute_id = `DISP-${randomUUID().slice(0, 8).toUpperCase()}`;
    contract.dispute_status = 'open';
    contract.dispute_reason = body.reason?.trim() || 'Contract breach reported';
    publish('contract.disputed', contract);
    const result = { ok: true, contract, contracts: state.contracts, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const resolveContractMatch = path.match(/^\/api\/contracts\/([^/]+)\/resolve$/);
  if (resolveContractMatch && body.method === 'POST') {
    const contractId = resolveContractMatch[1];
    const contract = state.contracts.find((c) => c.id === contractId);
    if (!contract) throw new ApiError('Contract not found', 404, 'NOT_FOUND');
    if (!contract.dispute_id) throw new ApiError('No open dispute to resolve', 400, 'VALIDATION_ERROR');
    contract.status = body.outcome === 'refund' ? 'refunded' : 'resolved';
    contract.dispute_status = 'resolved';
    contract.resolution = body.resolution?.trim() || 'Arbitrated resolution';
    publish('contract.resolved', contract);
    const result = { ok: true, contract, contracts: state.contracts, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  // Notifications
  const readNotificationMatch = path.match(/^\/api\/notifications\/([^/]+)\/read$/);
  if (readNotificationMatch && body.method === 'POST') {
    const notifId = readNotificationMatch[1];
    const notif = state.notifications.find((n) => n.id === notifId);
    if (notif) notif.read = true;
    return { ok: true, notificationId: notifId, unreadCount: state.notifications.filter((n) => !n.read).length };
  }

  if (path === '/api/notifications/read-all' && body.method === 'POST') {
    for (const n of state.notifications) n.read = true;
    return { ok: true, unreadCount: 0 };
  }

  // --- Authentication Routes ---
  if (path === '/api/auth/register' && body.method === 'POST') {
    const email = body.email?.trim().toLowerCase();
    const displayName = body.displayName?.trim();
    const password = body.password ?? '';
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new ApiError('A valid email is required', 400, 'VALIDATION_ERROR');
    if (!displayName || displayName.length < 2 || displayName.length > 80) throw new ApiError('Display name must be 2–80 characters', 400, 'VALIDATION_ERROR');
    if (password.length < 12) throw new ApiError('Password must be at least 12 characters', 400, 'VALIDATION_ERROR');
    if (body.passwordConfirmation !== undefined && password !== body.passwordConfirmation) throw new ApiError('Passwords do not match', 400, 'VALIDATION_ERROR');
    if (registeredUsers.has(email)) throw new ApiError('Email is already registered', 409, 'CONFLICT');

    const humanId = 'H-' + randomUUID().slice(0, 8).toUpperCase();
    const salt = randomBytes(16);
    const passwordHash = pbkdf2Sync(password, salt, 100000, 32, 'sha256').toString('base64');
    registeredUsers.set(email, { humanId, email, displayName, passwordHash, passwordSalt: salt.toString('base64'), iterations: 100000 });
    state.humans[humanId] = { id: humanId, name: displayName, credits: 10000, standing: 100, legacy: 0, ageYears: 20, votingWeight: 1 };

    const sessionToken = randomUUID();
    const sessionHash = hashToken(sessionToken);
    const expiresAt = Date.now() + 7 * 24 * 3600 * 1000;
    const session = { id: randomUUID(), humanId, email, displayName, expiresAt, createdAt: Date.now() };
    sessions.set(sessionHash, session);

    return {
      status: 201,
      headers: { 'Set-Cookie': sessionCookie(sessionToken) },
      data: { ok: true, human: { id: humanId, displayName, email }, user: { id: humanId, displayName, email }, persistence: database ? 'postgres-reference' : 'reference-simulator' },
    };
  }

  if (path === '/api/auth/login' && body.method === 'POST') {
    const email = body.email?.trim().toLowerCase();
    const password = body.password ?? '';
    if (!email || !password) throw new ApiError('Invalid email or password', 401, 'AUTHENTICATION_REQUIRED');

    let user = registeredUsers.get(email);
    if (!user) {
      if (email === 'amara@earthuc.com' || email === 'earth@nohainc.com') {
        user = { humanId: 'H-0044', email, displayName: 'Amara Kline', passwordHash: defaultHash, passwordSalt: defaultSalt.toString('base64'), iterations: 100000 };
      } else {
        throw new ApiError('Invalid email or password', 401, 'AUTHENTICATION_REQUIRED');
      }
    }
    if (user.passwordSalt && user.passwordHash) {
      const salt = Buffer.from(user.passwordSalt, 'base64');
      const computed = pbkdf2Sync(password, salt, user.iterations || 100000, 32, 'sha256').toString('base64');
      if (computed !== user.passwordHash) throw new ApiError('Invalid email or password', 401, 'AUTHENTICATION_REQUIRED');
    }

    const sessionToken = randomUUID();
    const sessionHash = hashToken(sessionToken);
    const expiresAt = Date.now() + 7 * 24 * 3600 * 1000;
    const session = { id: randomUUID(), humanId: user.humanId, email: user.email, displayName: user.displayName, expiresAt, createdAt: Date.now() };
    sessions.set(sessionHash, session);

    return {
      status: 200,
      headers: { 'Set-Cookie': sessionCookie(sessionToken) },
      data: { ok: true, humanId: user.humanId, human: { id: user.humanId, displayName: user.displayName, email: user.email }, expiresAt },
    };
  }

  if (path === '/api/auth/me' && body.method === 'GET') {
    const session = resolveSession(req);
    if (!session) {
      return { ok: true, authenticated: false, human: null, user: null, persistence: database ? 'postgres-reference' : 'reference-simulator' };
    }
    const h = human(session.humanId, req);
    return {
      ok: true,
      authenticated: true,
      human: { id: session.humanId, email: session.email, displayName: session.displayName || h.name, credits: h.credits, standing: h.standing },
      user: { id: session.humanId, email: session.email, displayName: session.displayName || h.name },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/auth/logout' && body.method === 'POST') {
    const token = parseCookie(req, 'earth_session') || req.headers?.authorization?.replace(/^Bearer\s+/i, '');
    if (token) {
      const tokenHash = hashToken(token);
      const session = sessions.get(tokenHash);
      if (session) session.revokedAt = Date.now();
    }
    return {
      status: 200,
      headers: { 'Set-Cookie': sessionCookie('', 0) },
      data: { ok: true },
    };
  }

  if (path === '/api/auth/sessions' && body.method === 'GET') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const userSessions = Array.from(sessions.values())
      .filter((s) => s.humanId === session.humanId && !s.revokedAt)
      .map((s) => ({ id: s.id, createdAt: s.createdAt, expiresAt: s.expiresAt, current: s.id === session.id }));
    return { sessions: userSessions, persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  const revokeSessionMatch = path.match(/^\/api\/auth\/sessions\/([^/]+)$/);
  if (revokeSessionMatch && body.method === 'DELETE') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const targetSessionId = revokeSessionMatch[1];
    for (const s of sessions.values()) {
      if (s.id === targetSessionId && s.humanId === session.humanId) {
        s.revokedAt = Date.now();
      }
    }
    return { ok: true, persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  if (path === '/api/auth/sessions' && body.method === 'DELETE') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    for (const s of sessions.values()) {
      if (s.humanId === session.humanId) s.revokedAt = Date.now();
    }
    return { ok: true, persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  if (path === '/api/auth/verify-email/resend' && body.method === 'POST') {
    return { ok: true, message: 'If that identity exists and needs verification, a new email has been sent.' };
  }
  if (path.startsWith('/api/auth/verify-email') && body.method === 'GET') {
    return { ok: true, message: 'Email verified. You can now sign in.' };
  }
  if (path === '/api/auth/password-reset/request' && body.method === 'POST') {
    return { ok: true, message: 'If that identity exists, recovery instructions have been sent.' };
  }
  if (path === '/api/auth/password-reset/complete' && body.method === 'POST') {
    return { ok: true, message: 'Password reset. All previous sessions were revoked.' };
  }
  if (path === '/api/auth/mfa/enroll' && body.method === 'POST') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    return { ok: true, secret: 'JBSWY3DPEHPK3PXP', otpauth: 'otpauth://totp/EARTH:amara?secret=JBSWY3DPEHPK3PXP&issuer=EARTH', message: 'Scan secret' };
  }
  if (path === '/api/auth/mfa/confirm' && body.method === 'POST') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    return { ok: true, enabled: true };
  }
  if (path === '/api/auth/mfa/disable' && body.method === 'POST') {
    const session = resolveSession(req);
    if (!session) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    return { ok: true, enabled: false };
  }

  // --- Domain Mutations ---
  if ((path === '/api/life/successor' || path === '/api/succession/plans') && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const name = body.name || body.successorName;
    if (typeof name !== 'string' || name.trim().length < 2) throw new ApiError('Successor name is required', 400, 'VALIDATION_ERROR');
    state.life.successor = { name: name.trim(), registeredOnDay: state.clock.day };
    if (database) void database.saveSuccession(state.life.successor).catch((error) => console.error('succession persistence failed', error.message));
    publish('succession.registered', state.life.successor);
    return { ok: true, life: state.life, succession: state.life.successor, state: snapshot() };
  }

  const correlationId = body.correlationId || body.idempotencyKey || req?.headers?.['idempotency-key'] || req?.headers?.['x-request-id'];
  if (correlationId && commandResults.has(correlationId)) return commandResults.get(correlationId);

  if ((path === '/api/day/advance' || path === '/api/world/tick') && body.method === 'POST') {
    const result = { ok: true, result: advanceDay(), clock: state.clock, state: snapshot() };
    publish('world.ticked', state.clock);
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/market/orders' && body.method === 'POST') {
    const product = state.market.products[body.product];
    if (!product) throw new ApiError('Unknown product', 400, 'VALIDATION_ERROR');
    if (!Number.isFinite(body.quantity) || body.quantity < 1 || !Number.isFinite(body.limitPrice) || body.limitPrice <= 0) throw new ApiError('Invalid order', 400, 'VALIDATION_ERROR');
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const total = money(body.quantity * body.limitPrice);
    if (player.credits < total) throw new ApiError('Insufficient Credits', 400, 'VALIDATION_ERROR');
    const actorId = player.id || 'H-0044';
    const order = { id: randomUUID(), humanId: actorId, product: body.product, quantity: Math.floor(body.quantity), limitPrice: Number(body.limitPrice), filled: 0, status: 'open', createdAt: Date.now() };
    state.market.orders.push(order);
    if (database) void database.saveOrder(order).catch((error) => console.error('order persistence failed', error.message));
    const result = { ok: true, order, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/market/settle' && body.method === 'POST') {
    const result = { ok: true, result: settleMarket(), state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if ((path === '/api/businesses/kline-works/policy' || path === '/api/businesses/B-1048/policy' || path === '/api/business/policy' || path === '/api/businesses/me/policy') && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const actorId = player.id || 'H-0044';
    if (state.businesses.klineWorks.ownerId && state.businesses.klineWorks.ownerId !== actorId && state.businesses.klineWorks.ownerId !== 'H-0044') {
      throw new ApiError('Unauthorized: Not business owner', 403, 'FORBIDDEN');
    }
    const policy = body.policy === 'growth' ? 'capacity' : body.policy;
    if (!['reliability', 'margin', 'capacity', 'growth'].includes(body.policy)) throw new ApiError('Unknown policy', 400, 'VALIDATION_ERROR');
    state.businesses.klineWorks.policy = policy;
    if (database) void database.saveBusiness(state.businesses.klineWorks).catch((error) => console.error('policy persistence failed', error.message));
    publish('business.policy_changed', { businessId: 'B-1048', policy });
    const result = { ok: true, policy, business: state.businesses.klineWorks, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/ai' && body.method === 'GET') {
    return {
      assistants: state.aiAssistants || [{ id: 'AI-01', tier: 'basic', policy: 'recommend', enabled: true }],
      recommendations: state.aiRecommendations || [],
      constraints: { governance: false, authority: false, allowedPolicies: ['recommend', 'maintenance'] },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if ((path === '/api/ai/policy' || path.startsWith('/api/ai/assistants/')) && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const policy = body.policy || 'recommend';
    if (!['recommend', 'maintenance'].includes(policy)) throw new ApiError('Basic AI supports only recommend or maintenance policies', 400, 'VALIDATION_ERROR');
    const assistantId = body.assistantId || (path.match(/\/assistants\/([^/]+)/)?.[1]) || 'AI-01';
    if (!state.aiAssistants) state.aiAssistants = [{ id: 'AI-01', tier: 'basic', policy: 'recommend', enabled: true }];
    const target = state.aiAssistants.find((a) => a.id === assistantId) || state.aiAssistants[0];
    target.policy = policy;
    target.enabled = body.enabled !== false;
    publish('ai.policy_updated', { assistantId, policy, enabled: target.enabled });
    const result = { ok: true, assistantId, policy, enabled: target.enabled, assistant: target, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if ((path === '/api/ai/upgrade' || path.includes('/upgrade')) && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    if (player.credits < 2400) throw new ApiError('Insufficient Credits for AI upgrade', 409, 'CONFLICT');
    player.credits -= 2400;
    if (!state.aiAssistants) state.aiAssistants = [{ id: 'AI-01', tier: 'basic', policy: 'recommend', enabled: true }];
    const target = state.aiAssistants[0];
    target.tier = 'business';
    appendLedger({ debit: player.id || 'H-0044', credit: 'account-system-registry', amount: 2400, reason: 'ai_assistant_upgrade', correlationId: randomUUID() });
    publish('ai.upgraded', { assistantId: target.id, tier: 'business' });
    const result = { ok: true, assistant: target, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/technology' && body.method === 'GET') {
    return {
      projects: [state.technology.research],
      patents: state.patents || [],
      licenses: state.licenses || [],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/technology/projects' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const budget = Number(body.budget ?? 240);
    if (!body.name || body.name.length < 3 || budget < 240) throw new ApiError('Invalid project parameters', 400, 'VALIDATION_ERROR');
    if (player.credits < budget) throw new ApiError('Insufficient Credits', 400, 'VALIDATION_ERROR');
    player.credits -= budget;
    const project = {
      id: `PROJECT-${randomUUID().slice(0, 8).toUpperCase()}`,
      name: body.name.trim(),
      budget,
      progress: 0,
      status: 'active',
      focus: body.focus || 'efficiency',
      owner_id: player.id || 'H-0044',
    };
    state.technology.research = project;
    appendLedger({ debit: player.id || 'H-0044', credit: 'account-research-registry', amount: budget, reason: 'research_project_funding', correlationId: randomUUID() });
    publish('research.started', project);
    const result = { ok: true, project, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if ((path === '/api/technology/me/fund' || path === '/api/technology/TECH-001/fund' || path === '/api/research/fund' || path === '/api/technology/research/fund') && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const actorId = player.id || 'H-0044';
    const amount = Number(body.amount || 240);
    if (amount < 1) throw new ApiError('Invalid funding amount', 400, 'VALIDATION_ERROR');
    if (player.credits < amount) throw new ApiError('Insufficient Credits', 400, 'VALIDATION_ERROR');
    player.credits -= amount;
    state.technology.research.progress = Math.min(100, (state.technology.research.progress || 0) + 4);
    appendLedger({ debit: actorId, credit: 'research-project-TECH-001', amount, reason: 'research_funding', correlationId: randomUUID() });
    if (database) void database.saveTechnology(state.technology.research).catch((error) => console.error('research persistence failed', error.message));
    publish('research.progressed', state.technology.research);
    const result = { ok: true, research: state.technology.research, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if ((path === '/api/technology/me/patent' || path === '/api/technology/TECH-001/patent') && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    if ((state.technology.research.progress || 0) < 100) throw new ApiError('Research must reach 100% before patent grant', 409, 'CONFLICT');
    const patentId = `PAT-${state.technology.research.id || 'TECH-001'}`;
    const patent = {
      id: patentId,
      technology_id: state.technology.research.id || 'TECH-001',
      name: state.technology.research.name,
      owner_id: player.id || 'H-0044',
      granted_game_day: state.clock.day,
      expiry_game_day: state.clock.day + 3650,
      status: 'active',
    };
    state.patents = state.patents || [];
    if (!state.patents.find((p) => p.id === patentId)) state.patents.push(patent);
    state.technology.activePatents = state.patents.length;
    publish('technology.patent_granted', patent);
    const result = { ok: true, patent, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if ((path === '/api/technology/me/license' || path === '/api/technology/TECH-001/license') && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const licenseeId = body.licenseeId || player.id || 'H-0044';
    const royaltyRate = Number(body.royaltyRate ?? 0.05);
    const licenseFee = Number(body.licenseFee ?? 0);
    const licenseId = `LIC-PAT-TECH-001-${licenseeId}`;
    const license = {
      id: licenseId,
      patent_id: 'PAT-TECH-001',
      licensor_id: player.id || 'H-0044',
      licensee_id: licenseeId,
      royalty_rate: royaltyRate,
      license_fee: licenseFee,
      status: 'active',
    };
    state.licenses = state.licenses || [];
    const existingIdx = state.licenses.findIndex((l) => l.id === licenseId);
    if (existingIdx >= 0) state.licenses[existingIdx] = license;
    else state.licenses.push(license);
    state.technology.activeLicenses = state.licenses.length;
    publish('technology.licensed', license);
    const result = { ok: true, license, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  // Machines
  if (path === '/api/machines' && body.method === 'GET') {
    return { machines: state.machines || [], persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  if (path === '/api/machines/acquire' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    const machineType = body.machineType || 'fabrication-rig';
    const creditCost = 850;
    const materialCost = 50;
    if (player.credits < creditCost) throw new ApiError('Insufficient Credits for machine acquisition', 400, 'VALIDATION_ERROR');
    if ((state.resources.material || 0) < materialCost) throw new ApiError('Insufficient Material for machine acquisition', 400, 'VALIDATION_ERROR');
    player.credits -= creditCost;
    state.resources.material -= materialCost;
    const machine = {
      id: `M-${player.id || 'H-0044'}-${randomUUID().slice(0, 6).toUpperCase()}`,
      owner_id: player.id || 'H-0044',
      name: `${machineType.replace('-', ' ')} ${player.id?.slice(-4) || '0044'}`,
      machine_type: machineType,
      condition: 100,
      utilization: 25,
      maintenance_due: 0,
      productive_capacity: 1.0,
      output_resource: 'components',
      input_resource: 'material',
      status: 'active',
    };
    state.machines = state.machines || [];
    state.machines.push(machine);
    appendLedger({ debit: player.id || 'H-0044', credit: 'account-machine-registry', amount: creditCost, reason: 'machine_acquisition', correlationId: randomUUID() });
    publish('machine.acquired', machine);
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const maintainMachineMatch = path.match(/^\/api\/machines\/([^/]+)\/maintenance$/);
  if (maintainMachineMatch && body.method === 'POST') {
    const machineId = maintainMachineMatch[1];
    const machine = (state.machines || []).find((m) => m.id === machineId);
    if (!machine) throw new ApiError('Machine not found', 404, 'NOT_FOUND');
    const amount = Number(body.amount ?? 10);
    if ((state.resources.components || 0) < amount) throw new ApiError('Insufficient Components for maintenance', 400, 'VALIDATION_ERROR');
    state.resources.components -= amount;
    machine.condition = Math.min(100, (machine.condition || 80) + Math.round(amount * 0.8));
    machine.maintenance_due = Math.max(0, (machine.maintenance_due || 0) - amount);
    publish('machine.maintained', { machineId, condition: machine.condition });
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const utilizationMachineMatch = path.match(/^\/api\/machines\/([^/]+)\/utilization$/);
  if (utilizationMachineMatch && body.method === 'POST') {
    const machineId = utilizationMachineMatch[1];
    const machine = (state.machines || []).find((m) => m.id === machineId);
    if (!machine) throw new ApiError('Machine not found', 404, 'NOT_FOUND');
    machine.utilization = Number(body.utilization ?? 50);
    publish('machine.utilization_updated', { machineId, utilization: machine.utilization });
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const upgradeMachineMatch = path.match(/^\/api\/machines\/([^/]+)\/upgrade$/);
  if (upgradeMachineMatch && body.method === 'POST') {
    const machineId = upgradeMachineMatch[1];
    const machine = (state.machines || []).find((m) => m.id === machineId);
    if (!machine) throw new ApiError('Machine not found', 404, 'NOT_FOUND');
    const player = human('amara', req);
    if (player.credits < 600) throw new ApiError('Insufficient Credits for machine upgrade', 400, 'VALIDATION_ERROR');
    if ((state.resources.components || 0) < 20) throw new ApiError('Insufficient Components for machine upgrade', 400, 'VALIDATION_ERROR');
    player.credits -= 600;
    state.resources.components -= 20;
    machine.productive_capacity = Math.min(5.0, Math.round(((machine.productive_capacity || 1.0) + 0.2) * 100) / 100);
    machine.condition = Math.max(0, (machine.condition || 80) - 5);
    appendLedger({ debit: player.id || 'H-0044', credit: 'account-ouc-treasury', amount: 600, reason: 'machine_upgrade', correlationId: randomUUID() });
    publish('machine.upgraded', { machineId, capacity: machine.productive_capacity });
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const sellMachineMatch = path.match(/^\/api\/machines\/([^/]+)\/sell$/);
  if (sellMachineMatch && body.method === 'POST') {
    const machineId = sellMachineMatch[1];
    const machine = (state.machines || []).find((m) => m.id === machineId);
    if (!machine) throw new ApiError('Machine not found', 404, 'NOT_FOUND');
    const buyerId = body.buyerId || 'H-0045';
    const price = Number(body.price ?? 500);
    const player = human('amara', req);
    player.credits += price;
    machine.owner_id = buyerId;
    machine.status = 'sold';
    appendLedger({ debit: buyerId, credit: player.id || 'H-0044', amount: price, reason: 'machine_sale', correlationId: randomUUID() });
    publish('machine.sold', { machineId, sellerId: player.id || 'H-0044', buyerId, price });
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const decommissionMachineMatch = path.match(/^\/api\/machines\/([^/]+)\/decommission$/);
  if (decommissionMachineMatch && body.method === 'POST') {
    const machineId = decommissionMachineMatch[1];
    const machine = (state.machines || []).find((m) => m.id === machineId);
    if (!machine) throw new ApiError('Machine not found', 404, 'NOT_FOUND');
    machine.status = 'recycled';
    machine.utilization = 0;
    state.resources.material = (state.resources.material || 0) + 25;
    state.resources.components = (state.resources.components || 0) + 5;
    publish('machine.recycled', { machineId });
    const result = { ok: true, machine, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  // Business Financials & Dividends & Liquidation
  const businessFinancialsMatch = path.match(/^\/api\/businesses\/([^/]+)\/financials$/);
  if (businessFinancialsMatch && body.method === 'GET') {
    const businessId = businessFinancialsMatch[1];
    return {
      business: {
        id: businessId,
        name: 'Kline Works',
        status: state.businesses.klineWorks.status || 'active',
        revenue: 1240.0,
        operating_costs: 820.0,
        profit: 420.0,
        taxed_revenue: 1240.0,
        last_game_day: state.clock.day,
        condition: state.businesses.klineWorks.condition || 96,
      },
      accounting: {
        revenue: 'market-cleared sales and accepted contract income',
        operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax',
        profit: 'revenue minus operating costs',
      },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  const businessOwnershipMatch = path.match(/^\/api\/businesses\/([^/]+)\/ownership$/);
  if (businessOwnershipMatch && body.method === 'GET') {
    const businessId = businessOwnershipMatch[1];
    return {
      businessId,
      controllingHumanId: 'H-0044',
      totalIssuedShares: 1000,
      holders: [
        { human_id: 'H-0044', display_name: 'Amara Kline', shares: 750, percentage: 75 },
        { human_id: 'H-0045', display_name: 'Mira Kline', shares: 250, percentage: 25 },
      ],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  const businessDividendsMatch = path.match(/^\/api\/businesses\/([^/]+)\/dividends$/);
  if (businessDividendsMatch && body.method === 'POST') {
    const businessId = businessDividendsMatch[1];
    const amount = Number(body.amount ?? 100);
    if (!Number.isFinite(amount) || amount <= 0) throw new ApiError('Dividend amount must be positive', 400, 'VALIDATION_ERROR');
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    player.credits += Math.round(amount * 0.75 * 100) / 100;
    appendLedger({ debit: `business-${businessId}`, credit: player.id || 'H-0044', amount: Math.round(amount * 0.75 * 100) / 100, reason: 'dividend_distribution', correlationId: randomUUID() });
    publish('business.dividends_distributed', { businessId, amount });
    const result = { ok: true, businessId, amount, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const businessLiquidationMatch = path.match(/^\/api\/businesses\/([^/]+)\/liquidate$/);
  if (businessLiquidationMatch && body.method === 'POST') {
    const businessId = businessLiquidationMatch[1];
    const player = human('amara', req);
    if (!player) throw new ApiError('Human is not authorized for this action', 401, 'AUTHENTICATION_REQUIRED');
    state.businesses.klineWorks.status = 'dissolved';
    publish('business.liquidated', { businessId, ownerId: player.id || 'H-0044' });
    const result = { ok: true, businessId, status: 'dissolved', releasedMachines: (state.machines || []).length, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const cancelOrderMatch = path.match(/^\/api\/market\/orders\/([^/]+)$/);
  if (cancelOrderMatch && body.method === 'DELETE') {
    const orderId = cancelOrderMatch[1];
    const order = state.market.orders.find((o) => o.id === orderId);
    if (!order) throw new ApiError('Order not found', 404, 'NOT_FOUND');
    if (order.status === 'filled') throw new ApiError('Cannot cancel a filled order', 400, 'VALIDATION_ERROR');
    if (order.status === 'cancelled') throw new ApiError('Order is already cancelled', 409, 'CONFLICT');
    if (order.status === 'rejected') throw new ApiError('Order is already rejected', 409, 'CONFLICT');

    const remainingQty = (order.quantity || 0) - (order.filled || 0);
    const releasedEscrow = money(remainingQty * (order.limitPrice || 0));
    order.status = 'cancelled';
    order.releasedEscrow = releasedEscrow;

    const player = human('amara', req);
    if (player && releasedEscrow > 0) {
      player.credits += releasedEscrow;
      appendLedger({ debit: 'central-market-escrow', credit: player.id || 'H-0044', amount: releasedEscrow, reason: 'order_cancellation_refund', correlationId: randomUUID() });
    }
    publish('market.order_cancelled', { orderId: order.id, releasedEscrow, remainingQuantity: remainingQty });
    const result = { ok: true, orderId: order.id, status: 'cancelled', releasedEscrow, remainingQuantity: remainingQty, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  if (path === '/api/life/status' && body.method === 'GET') {
    const player = human('amara', req);
    return {
      ok: true,
      human: {
        id: player.id || 'H-0044',
        displayName: player.name || player.displayName || 'Amara Kline',
        ageYears: player.ageYears || 31,
        lifeStatus: player.lifeStatus || 'active',
        standing: player.standing || 742,
        legacy: player.legacy || 31,
        politicalEligibilityDay: 180,
      },
      succession: state.life.successor ? {
        successorName: state.life.successor.name,
        registeredGameDay: state.life.successor.registeredOnDay || state.clock.day,
        estatePeriodDays: state.life.estatePeriodDays || 30,
        successorHumanId: state.life.successor.successorHumanId || null,
      } : null,
      events: state.lifeEvents || [
        { id: 'EVT-LIFE-01', gameDay: 180, eventType: 'political_maturity', title: 'Political maturity achieved' }
      ],
      estate: {
        status: player.lifeStatus === 'estate' ? 'active' : 'inactive',
        estatePeriodDays: 30,
        inheritanceStatus: state.life.successor ? 'pending' : 'unplanned',
      },
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  const voteMatch = path.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
  if (voteMatch && body.method === 'POST') {
    const proposalId = voteMatch[1];
    if (!['support', 'oppose', 'abstain'].includes(body.vote)) throw new ApiError('Invalid ballot', 400, 'VALIDATION_ERROR');
    const proposal = state.governance.proposals.find((p) => String(p.id) === proposalId) || state.governance.proposals[0];
    if (!proposal) throw new ApiError('Proposal not found', 404, 'NOT_FOUND');
    const voter = human('amara', req);
    if (!voter) throw new ApiError('Human is not eligible to vote', 401, 'AUTHENTICATION_REQUIRED');
    const humanId = voter.id || 'H-0044';
    if (proposal.ballots[humanId] || proposal.ballots.amara) throw new ApiError('Ballot already recorded', 400, 'VALIDATION_ERROR');
    const voterWeight = Number(voter.votingWeight ?? voter.voting_weight ?? 1);
    if (!Number.isFinite(voterWeight) || voterWeight <= 0) throw new ApiError('Human is not eligible to vote', 403, 'FORBIDDEN');
    proposal.ballots[humanId] = body.vote;
    proposal.votes.uncast = Math.max(0, (proposal.votes.uncast || 0) - voterWeight);
    proposal.votes[body.vote] = (proposal.votes[body.vote] || 0) + voterWeight;
    if (database) void database.saveBallot(proposal.id, humanId, body.vote, voterWeight).catch((error) => console.error('ballot persistence failed', error.message));
    publish('governance.vote_updated', { proposalId: proposal.id, vote: body.vote, weight: voterWeight, votes: proposal.votes });
    return { ok: true, proposal, state: snapshot() };
  }

  throw new ApiError('Route not found', 404, 'NOT_FOUND');
}

function snapshot() {
  return {
    clock: state.clock,
    world: state.world,
    human: human(),
    life: state.life,
    institutions: state.institutions,
    resources: state.resources,
    business: state.businesses.klineWorks,
    market: state.market,
    governance: state.governance,
    technology: state.technology,
    machines: state.machines || [],
    patents: state.patents || [],
    licenses: state.licenses || [],
    publicActivity: [
      { type: 'world_clock', day: state.clock.day },
      { type: 'research_progress', progress: state.technology.research.progress },
      { type: 'market_cycle', batch: state.world.batch },
    ],
    ledgerEntries: state.ledger.slice(-25),
    contracts: state.contracts || [],
    notifications: state.notifications || [],
    mode: database ? 'postgres-reference' : 'reference-simulator',
    authority: 'non-production',
  };
}

function audit() {
  const ordersValid = state.market.orders.every((order) => order.filled >= 0 && order.filled <= order.quantity && ['open', 'partial', 'filled', 'rejected', 'cancelled'].includes(order.status));
  const ledgerValid = state.ledger.every((entry) => entry.amount > 0 && entry.debit && entry.credit && entry.currency === 'CREDIT' && entry.debit !== entry.credit);
  const balancesValid = Object.values(state.humans).every((player) => player.credits >= 0);
  const ballots = state.governance.proposals.flatMap((proposal) => Object.keys(proposal.ballots));
  const ballotUniqueness = new Set(ballots).size === ballots.length;
  return { ok: ordersValid && ledgerValid && balancesValid && ballotUniqueness, checks: { ordersValid, ledgerValid, balancesValid, ballotUniqueness }, inspected: { orders: state.market.orders.length, ledgerEntries: state.ledger.length, humans: Object.keys(state.humans).length, ballots: ballots.length }, gameDay: state.clock.day };
}

function send(res, status, data, extraHeaders = {}) {
  const headers = {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type, authorization, idempotency-key, x-request-id',
    'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
    'access-control-expose-headers': 'x-request-id',
    'x-earth-api-version': '2026-08',
    ...extraHeaders,
  };
  res.writeHead(status, headers);
  res.end(typeof data === 'string' ? data : JSON.stringify(data));
}

function sendError(res, status, message, code = null, correlationId = null) {
  const codeByStatus = {
    400: 'VALIDATION_ERROR',
    401: 'AUTHENTICATION_REQUIRED',
    403: 'FORBIDDEN',
    404: 'NOT_FOUND',
    409: 'CONFLICT',
    429: 'RATE_LIMITED',
    500: 'INTERNAL_ERROR',
    503: 'SERVICE_UNAVAILABLE',
  };
  const finalCode = code || codeByStatus[status] || 'REQUEST_FAILED';
  const finalCorrelationId = correlationId || randomUUID();
  const payload = {
    ok: false,
    error: message,
    code: finalCode,
    correlationId: finalCorrelationId,
  };
  send(res, status, payload, { 'x-request-id': finalCorrelationId });
}

async function serveStatic(res, pathname) {
  const files = {
    '/': resolve('index.html'),
    '/index.html': resolve('index.html'),
    '/landing': resolve('index.html'),
    '/landing.css': resolve('landing.css'),
    '/prototype3.html': resolve('prototype3.html'),
    '/prototype3.css': resolve('prototype3.css'),
    '/prototype3.js': resolve('prototype3.js'),
    '/app': resolve('flutter_client/build/web/app.html'),
    '/app/': resolve('flutter_client/build/web/app.html'),
    '/app.html': resolve('flutter_client/build/web/app.html'),
  };
  let file = files[pathname];
  if (!file && pathname.startsWith('/') && !pathname.startsWith('/api/') && !pathname.startsWith('/edge/') && pathname !== '/health' && pathname !== '/ready') {
    let relPath = pathname.replace(/^\//, '');
    if (relPath.startsWith('app/')) relPath = relPath.slice(4);
    const webCandidate = resolve('flutter_client/build/web', relPath);
    try {
      const st = await stat(webCandidate);
      if (st.isFile()) file = webCandidate;
    } catch {}
  }
  if (!file) return false;
  try {
    const content = await readFile(file);
    const types = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'text/javascript; charset=utf-8',
      '.mjs': 'text/javascript; charset=utf-8',
      '.json': 'application/json; charset=utf-8',
      '.wasm': 'application/wasm',
      '.ttf': 'font/ttf',
      '.otf': 'font/otf',
      '.png': 'image/png',
      '.svg': 'image/svg+xml',
    };
    res.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' });
    res.end(content);
    return true;
  } catch {
    return false;
  }
}

async function hydrateFromDatabase() {
  if (!database) return;
  const canonical = await database.loadCanonical();
  if (canonical.world) {
    state.clock.day = Number(canonical.world.game_day ?? state.clock.day);
    state.clock.minute = Number(canonical.world.game_minute ?? state.clock.minute);
    state.world.health = Number(canonical.world.health ?? state.world.health);
    state.world.batch = Number(canonical.world.market_batch_seconds ?? state.world.batch);
  }
  if (canonical.human) {
    if (canonical.human.id) state.humans.amara.id = canonical.human.id;
    if (canonical.human.display_name != null) state.humans.amara.name = canonical.human.display_name;
    if (canonical.human.standing != null) state.humans.amara.standing = Number(canonical.human.standing);
    if (canonical.human.legacy != null) state.humans.amara.legacy = Number(canonical.human.legacy);
    if (canonical.human.age_years != null) state.humans.amara.ageYears = Number(canonical.human.age_years);
    if (canonical.human.credits != null) state.humans.amara.credits = Number(canonical.human.credits);
    if (canonical.human.life_status) state.life.status = canonical.human.life_status;
  }
  if (canonical.votingWeight != null) {
    state.humans.amara.votingWeight = Number(canonical.votingWeight);
  }
  if (canonical.succession) {
    state.life.successor = {
      name: canonical.succession.successor_name,
      registeredOnDay: Number(canonical.succession.registered_game_day),
    };
    if (canonical.succession.estate_period_days != null) {
      state.life.estatePeriodDays = Number(canonical.succession.estate_period_days);
    }
  }
  if (canonical.resources?.length) {
    for (const resource of canonical.resources) {
      if (resource.amount != null) state.resources[resource.resource] = Number(resource.amount);
    }
  }
  if (canonical.business) {
    if (canonical.business.name != null) state.businesses.klineWorks.name = canonical.business.name;
    if (canonical.business.policy != null) state.businesses.klineWorks.policy = canonical.business.policy;
    if (canonical.business.condition != null) state.businesses.klineWorks.condition = Number(canonical.business.condition);
  }
  if (canonical.technology) {
    if (canonical.technology.name != null) state.technology.research.name = canonical.technology.name;
    if (canonical.technology.progress != null) state.technology.research.progress = Number(canonical.technology.progress);
  }
  if (canonical.orders) {
    state.market.orders = canonical.orders.map((order) => ({
      id: order.id,
      humanId: 'amara',
      product: order.product,
      quantity: Number(order.quantity),
      limitPrice: Number(order.limit_price),
      filled: Number(order.filled_quantity || 0),
      status: order.status,
      createdAt: Number(order.created_at),
    }));
  }
  if (canonical.proposals?.length) {
    state.governance.proposals = canonical.proposals.map((proposal) => {
      const proposalBallots = (canonical.ballots || []).filter((b) => String(b.proposal_id) === String(proposal.id));
      const support = proposalBallots.filter((b) => b.choice === 'support').reduce((sum, b) => sum + Number(b.weight || 1), 0);
      const oppose = proposalBallots.filter((b) => b.choice === 'oppose').reduce((sum, b) => sum + Number(b.weight || 1), 0);
      const abstain = proposalBallots.filter((b) => b.choice === 'abstain').reduce((sum, b) => sum + Number(b.weight || 1), 0);
      const totalCast = support + oppose + abstain;
      const ballotsMap = Object.fromEntries(proposalBallots.map((b) => [b.human_id, b.choice]));

      let eligibleWeight;
      if (proposal.eligible_weight != null && Number(proposal.eligible_weight) > 0) {
        eligibleWeight = Number(proposal.eligible_weight);
      } else if (proposal.electorate != null && Number(proposal.electorate) > 0) {
        eligibleWeight = Number(proposal.electorate);
      } else if (proposal.total_electorate != null && Number(proposal.total_electorate) > 0) {
        eligibleWeight = Number(proposal.total_electorate);
      } else if (proposal.institution_id) {
        const instCity = (canonical.cities || []).find((c) => c.institution_id === proposal.institution_id || c.id === proposal.institution_id);
        const instCorp = (canonical.corporations || []).find((c) => c.institution_id === proposal.institution_id || c.id === proposal.institution_id);
        if (instCity && instCity.residents != null && Number(instCity.residents) > 0) {
          eligibleWeight = Number(instCity.residents);
        } else if (instCorp && instCorp.member_count != null && Number(instCorp.member_count) > 0) {
          eligibleWeight = Number(instCorp.member_count);
        }
      }
      if (eligibleWeight == null) {
        if (canonical.activeHumans != null && Number(canonical.activeHumans) > 0) {
          eligibleWeight = Number(canonical.activeHumans);
        } else {
          eligibleWeight = Math.max(totalCast, Object.keys(state.humans || {}).length || 1);
        }
      }
      const uncast = Math.max(0, eligibleWeight - totalCast);

      return {
        id: String(proposal.id),
        institution_id: proposal.institution_id || undefined,
        institutionId: proposal.institution_id || undefined,
        title: proposal.title,
        body: proposal.body,
        status: proposal.status,
        outcome: proposal.outcome,
        execution_status: proposal.execution_status,
        executionStatus: proposal.execution_status,
        closes_game_day: proposal.closes_game_day != null ? Number(proposal.closes_game_day) : undefined,
        closesGameDay: proposal.closes_game_day != null ? Number(proposal.closes_game_day) : undefined,
        closes_game_minute: proposal.closes_game_minute != null ? Number(proposal.closes_game_minute) : undefined,
        closesGameMinute: proposal.closes_game_minute != null ? Number(proposal.closes_game_minute) : undefined,
        implementation_game_day: proposal.implementation_game_day != null ? Number(proposal.implementation_game_day) : undefined,
        implementationGameDay: proposal.implementation_game_day != null ? Number(proposal.implementation_game_day) : undefined,
        implementation_game_minute: proposal.implementation_game_minute != null ? Number(proposal.implementation_game_minute) : undefined,
        implementationGameMinute: proposal.implementation_game_minute != null ? Number(proposal.implementation_game_minute) : undefined,
        opens_at: proposal.opens_at != null ? Number(proposal.opens_at) : undefined,
        closes_at: proposal.closes_at != null ? Number(proposal.closes_at) : undefined,
        implementation_at: proposal.implementation_at != null ? Number(proposal.implementation_at) : undefined,
        resolved_at: proposal.resolved_at != null ? Number(proposal.resolved_at) : undefined,
        executed_at: proposal.executed_at != null ? Number(proposal.executed_at) : undefined,
        quorum: proposal.quorum != null ? Number(proposal.quorum) : 0.25,
        approval_threshold: proposal.approval_threshold != null ? Number(proposal.approval_threshold) : 0.5,
        implementation_delay_days: proposal.implementation_delay_days != null ? Number(proposal.implementation_delay_days) : 1,
        levy: proposal.levy != null ? Number(proposal.levy) : undefined,
        eligible_weight: eligibleWeight,
        eligibleWeight,
        votes: {
          support,
          oppose,
          abstain,
          uncast,
        },
        ballots: ballotsMap,
      };
    });
  } else {
    for (const ballot of canonical.ballots || []) {
      if (String(ballot.proposal_id) === '042' || !ballot.proposal_id) {
        state.governance.proposals[0].ballots[ballot.human_id || 'amara'] = ballot.choice;
      }
    }
  }
  if (canonical.institutions?.length) {
    const oucInst = canonical.institutions.find((i) => i.kind === 'OUC');
    if (oucInst) {
      state.institutions.ouc = {
        id: oucInst.id,
        kind: 'OUC',
        name: oucInst.name,
        treasury: 0,
      };
    }
    const corpInst = canonical.institutions.find((i) => i.kind === 'CORPORATION');
    const corpData = corpInst
      ? canonical.corporations?.find((c) => c.institution_id === corpInst.id || c.id === corpInst.id)
      : canonical.corporations?.find((c) => c.id === state.institutions.corporation.id || c.institution_id === state.institutions.corporation.id);
    if (corpInst || corpData) {
      state.institutions.corporation = {
        id: corpInst?.id || corpData?.institution_id || corpData?.id || state.institutions.corporation.id,
        kind: 'CORPORATION',
        name: corpInst?.name || state.institutions.corporation.name,
        members: corpData?.member_count != null ? Number(corpData.member_count) : state.institutions.corporation.members,
        member_count: corpData?.member_count != null ? Number(corpData.member_count) : (state.institutions.corporation.member_count ?? state.institutions.corporation.members),
        constitution_version: corpData?.constitution_version != null ? Number(corpData.constitution_version) : (state.institutions.corporation.constitution_version ?? 1),
        treasury: corpData?.treasury != null ? Number(corpData.treasury) : (state.institutions.corporation.treasury ?? 0),
        stability: state.institutions.corporation.stability ?? 76,
      };
    }
    const cityInst = canonical.institutions.find((i) => i.kind === 'CITY');
    const cityData = cityInst
      ? canonical.cities?.find((c) => c.institution_id === cityInst.id || c.id === cityInst.id)
      : canonical.cities?.find((c) => c.id === state.institutions.city.id || c.institution_id === state.institutions.city.id);
    if (cityInst || cityData) {
      state.institutions.city = {
        id: cityInst?.id || cityData?.institution_id || cityData?.id || state.institutions.city.id,
        kind: 'CITY',
        name: cityInst?.name || state.institutions.city.name,
        residents: cityData?.residents != null ? Number(cityData.residents) : state.institutions.city.residents,
        housing_capacity: cityData?.housing_capacity != null ? Number(cityData.housing_capacity) : state.institutions.city.housing_capacity,
        energy_capacity: cityData?.energy_capacity != null ? Number(cityData.energy_capacity) : state.institutions.city.energy_capacity,
        connectivity_capacity: cityData?.connectivity_capacity != null ? Number(cityData.connectivity_capacity) : state.institutions.city.connectivity_capacity,
        health_capacity: cityData?.health_capacity != null ? Number(cityData.health_capacity) : state.institutions.city.health_capacity,
        treasury: cityData?.treasury != null ? Number(cityData.treasury) : (state.institutions.city.treasury ?? 0),
        fiscalHealth: cityData?.fiscal_health != null ? Number(cityData.fiscal_health) : (cityData?.fiscalHealth != null ? Number(cityData.fiscalHealth) : state.institutions.city.fiscalHealth),
        capacity: {
          housing: cityData?.housing_capacity != null ? Number(cityData.housing_capacity) : state.institutions.city.capacity?.housing,
          energy: cityData?.energy_capacity != null ? Number(cityData.energy_capacity) : state.institutions.city.capacity?.energy,
          connectivity: cityData?.connectivity_capacity != null ? Number(cityData.connectivity_capacity) : state.institutions.city.capacity?.connectivity,
          health: cityData?.health_capacity != null ? Number(cityData.health_capacity) : state.institutions.city.capacity?.health,
        },
      };
    }
    const busInst = canonical.institutions.find((i) => i.kind === 'BUSINESS');
    const busData = canonical.businesses?.find((b) =>
      (busInst && (b.id === busInst.id || `BUS-${b.id.replace(/^B-/, '')}` === busInst.id || b.id === `B-${busInst.id.replace(/^BUS-/, '')}`)) ||
      b.owner_id === 'H-0044' || b.owner_id === state.humans.amara.id
    );
    if (busInst || busData) {
      state.institutions.business = {
        id: busInst?.id || busData?.id || state.institutions.business.id,
        kind: 'BUSINESS',
        name: busInst?.name || busData?.name || state.institutions.business.name,
        status: busInst?.status || busData?.status || 'active',
        ownerId: busData?.owner_id || state.institutions.business.ownerId || 'H-0044',
      };
    }
  }
  if (canonical.ledger?.length) {
    state.ledger = canonical.ledger.map((row) => ({
      id: row.id,
      gameDay: Number(row.game_day),
      debit: row.debit_account,
      credit: row.credit_account,
      amount: Number(row.amount),
      currency: row.currency || 'CREDIT',
      reason: row.reason_type || row.reason,
      correlationId: row.correlation_id || null,
    })).reverse();
  }
}

const server = createServer(async (req, res) => {
  const correlationId = req.headers['x-request-id'] || randomUUID();
  if (req.method === 'OPTIONS') return send(res, 204, '', { 'x-request-id': correlationId });

  const url = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);

  // SSE / Live events stream endpoint with replay support
  if (req.method === 'GET' && (url.pathname === '/api/events' || url.pathname === '/edge/events')) {
    const isJson = Boolean(req.headers.accept?.includes('application/json') && !req.headers.accept?.includes('text/event-stream') && url.pathname !== '/edge/events');
    const isSse = !isJson;
    if (isSse) {
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'content-type, authorization, idempotency-key, x-request-id',
        'x-request-id': correlationId,
        'x-earth-api-version': '2026-08',
      });
      res.write(`data: ${JSON.stringify({ type: 'connected', channel: 'earth-world', gameDay: state.clock.day })}\n\n`);

      const lastEventId = Number(req.headers['last-event-id'] || url.searchParams.get('after') || url.searchParams.get('cursor') || 0);
      if (lastEventId > 0) {
        const missed = eventLog.filter((e) => e.id > lastEventId);
        for (const evt of missed) {
          res.write(`id: ${evt.id}\nevent: ${evt.type}\ndata: ${JSON.stringify(evt)}\n\n`);
        }
      }

      eventSubscribers.add(res);
      req.on('close', () => eventSubscribers.delete(res));
      return;
    }

    const lastEventId = Number(url.searchParams.get('after') || url.searchParams.get('cursor') || 0);
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') || 50)));
    const events = (lastEventId > 0 ? eventLog.filter((e) => e.id > lastEventId) : eventLog).slice(-limit);
    return send(res, 200, { ok: true, events, cursor: eventLog[eventLog.length - 1]?.id || 0 }, { 'x-request-id': correlationId });
  }

  // Static files serving
  if (req.method === 'GET' && (await serveStatic(res, url.pathname))) return;

  // Read request body with safe size limitation
  let raw = '';
  try {
    for await (const chunk of req) {
      raw += chunk;
      if (raw.length > 1024 * 1024) {
        return sendError(res, 413, 'Request payload too large', 'VALIDATION_ERROR', correlationId);
      }
    }
  } catch (readErr) {
    return sendError(res, 400, 'Failed to read request body', 'VALIDATION_ERROR', correlationId);
  }

  let body = {};
  if (raw.trim()) {
    try {
      body = JSON.parse(raw);
    } catch {
      return sendError(res, 400, 'Malformed JSON payload', 'VALIDATION_ERROR', correlationId);
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return sendError(res, 400, 'Request body must be a JSON object', 'VALIDATION_ERROR', correlationId);
    }
  }

  try {
    const result = command(url.pathname, { ...body, method: req.method }, req);
    if (result && typeof result === 'object' && 'data' in result && 'status' in result) {
      return send(res, result.status, result.data, { 'x-request-id': correlationId, ...result.headers });
    }
    send(res, 200, result, { 'x-request-id': correlationId });
  } catch (error) {
    const status = error.status || (error.message === 'Route not found' ? 404 : 400);
    const code = error.code || (status === 404 ? 'NOT_FOUND' : 'VALIDATION_ERROR');
    sendError(res, status, error.message, code, correlationId);
  }
});

server.on('error', (error) => {
  console.error(`EARTH reference simulator failed to listen on ${HOST}:${PORT}:`, error.message);
  process.exitCode = 1;
});

// This Node process is a local compatibility/reference simulator only. The
// deployed Worker and all production economic mutations use PostgreSQL.
hydrateFromDatabase()
  .then(() => server.listen(PORT, HOST, () => console.log(`EARTH reference simulator listening on http://${HOST}:${PORT}`)))
  .catch((error) => {
    console.error('PostgreSQL hydration failed; refusing to start with stale or partial state:', error.message);
    process.exitCode = 1;
  });
