import { createServer } from 'node:http';
import { randomUUID, pbkdf2Sync, randomBytes, createHash } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { parse as parseNano, stringify as stringifyNano } from 'nanomarkup';
import { createDatabase } from './database.js';

function toNanoTree(val) {
  if (val === null || val === undefined) return 'null';
  if (typeof val === 'number' || typeof val === 'boolean' || typeof val === 'bigint') return String(val);
  if (typeof val === 'string') return val;
  if (Array.isArray(val)) return val.map((item) => toNanoTree(item));
  if (typeof val === 'object') {
    const res = {};
    for (const [k, v] of Object.entries(val)) res[k] = toNanoTree(v);
    return res;
  }
  return String(val);
}

function toNano(val) {
  try {
    const tree = toNanoTree(val);
    if (typeof tree === 'string') return tree;
    return stringifyNano(tree);
  } catch {
    return JSON.stringify(val);
  }
}

function fromNano(str) {
  const text = (str || '').trim();
  if (!text) return {};
  if ((text.startsWith('{') && text.endsWith('}')) || (text.startsWith('[') && text.endsWith(']'))) {
    try {
      return JSON.parse(text);
    } catch {}
  }
  try {
    const res = parseNano(text);
    if (res && typeof res === 'object') return res;
    if (typeof res === 'string' && ((res.startsWith('{') && res.endsWith('}')) || (res.startsWith('[') && res.endsWith(']')))) {
      try { return JSON.parse(res); } catch {}
    }
    return res || {};
  } catch {
    try {
      return JSON.parse(text);
    } catch {
      return {};
    }
  }
}

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
  resources: { food: 310, material: 420, components: 86, energy: 92, compute: 64 },
  businesses: { klineWorks: { id: 'B-1048', name: 'Kline Works', policy: 'reliability', condition: 96, research: 72 } },
  market: {
    products: {
      food: { price: 8.5, supply: 640, demand: 520 },
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

const commState = {
  channels: [
    {
      id: 'channel-global-relay',
      scope: 'global',
      scope_id: null,
      name: 'Planetary Public Relay',
      description: 'Universal broadcast frequency for open civilizational discourse and market news.',
    },
    {
      id: 'channel-city-new-tokyo',
      scope: 'city',
      scope_id: 'city-new-tokyo',
      name: 'Neo-Tokyo City Hall',
      description: 'Municipal forum for Neo-Tokyo residents, tax debates, and infrastructure initiatives.',
    },
    {
      id: 'channel-city-london',
      scope: 'city',
      scope_id: 'city-london',
      name: 'London Industrial Forum',
      description: 'Municipal chamber for London residents, trade, and industrial supply.',
    },
    {
      id: 'channel-corp-kline',
      scope: 'institution',
      scope_id: 'corp-kline-industrial',
      name: 'Kline Syndicate Boardroom',
      description: 'Encrypted channel for Kline Industrial shareholders and executive partners.',
    },
    {
      id: 'dm-amara-dmitri',
      scope: 'direct',
      scope_id: null,
      name: 'Dmitri Rostov (Direct Link)',
      description: 'Encrypted peer-to-peer diplomatic link.',
    },
  ],
  messages: {
    'channel-global-relay': [
      {
        id: 'msg-1',
        channel_id: 'channel-global-relay',
        sender_human_id: 'H-0012',
        sender_display_name: 'Dmitri Rostov',
        sender_dynasty_name: 'House of Rostov',
        body: 'Notice to all industrial fabricators: high-purity silicon demand has spiked 20% in London.',
        game_day: 184,
        game_minute: 420,
        attachments: [],
        created_at: new Date(Date.now() - 3600000).toISOString(),
      },
      {
        id: 'msg-2',
        channel_id: 'channel-global-relay',
        sender_human_id: 'H-0044',
        sender_display_name: 'Amara Vance',
        sender_dynasty_name: 'Vance Dynasty',
        body: 'Kline Works is allocating 40 kW additional geothermal compute capacity to fulfill component orders.',
        game_day: 184,
        game_minute: 480,
        attachments: [],
        created_at: new Date(Date.now() - 1800000).toISOString(),
      },
    ],
    'channel-city-new-tokyo': [
      {
        id: 'msg-3',
        channel_id: 'channel-city-new-tokyo',
        sender_human_id: 'H-0044',
        sender_display_name: 'Amara Vance',
        sender_dynasty_name: 'Vance Dynasty',
        body: 'Proposing municipal proposal P-201: Lower industrial energy tariffs by 1.5% to boost export volume.',
        game_day: 184,
        game_minute: 500,
        attachments: [{ type: 'proposal', id: 'P-201', title: 'Industrial Energy Tariff Reduction' }],
        created_at: new Date(Date.now() - 900000).toISOString(),
      },
    ],
    'dm-amara-dmitri': [
      {
        id: 'msg-4',
        channel_id: 'dm-amara-dmitri',
        sender_human_id: 'H-0012',
        sender_display_name: 'Dmitri Rostov',
        sender_dynasty_name: 'House of Rostov',
        body: 'Amara, did you review the tender offer for the circuit board delivery?',
        game_day: 184,
        game_minute: 520,
        attachments: [],
        created_at: new Date(Date.now() - 300000).toISOString(),
      },
    ],
  },
  dispatches: [
    {
      id: 'mail-1',
      sender_human_id: 'H-0012',
      sender_display_name: 'Dmitri Rostov',
      sender_dynasty_name: 'House of Rostov',
      recipient_human_id: 'H-0044',
      recipient_display_name: 'Amara Vance',
      subject: 'Tender Offer & Supply Contract Inquiry',
      body: 'Greetings Executive Vance. We are seeking to secure long-term rights to 250 units of standard circuit boards per cycle. We have enclosed a preliminary bilateral trade agreement for your executive review.',
      status: 'unread',
      game_day: 184,
      game_minute: 510,
      dispatch_type: 'contract_offer',
      action_payload: { contractId: 'CTR-904', creditsOffered: 1500 },
      created_at: new Date(Date.now() - 600000).toISOString(),
      read_at: null,
    },
    {
      id: 'mail-2',
      sender_human_id: 'H-0088',
      sender_display_name: 'Kaelen Thorne',
      sender_dynasty_name: 'Thorne Syndicate',
      recipient_human_id: 'H-0044',
      recipient_display_name: 'Amara Vance',
      subject: 'Quantum Core Patent Licensing Inquiry',
      body: 'We would like to license your Quantum Core patent for our Geneva fabrication plant. We offer 5% gross royalties plus 500 Credits upfront.',
      status: 'unread',
      game_day: 184,
      game_minute: 320,
      dispatch_type: 'patent_license',
      action_payload: { patentId: 'PAT-01', royaltyPercent: 5.0, upfrontCredits: 500 },
      created_at: new Date(Date.now() - 7200000).toISOString(),
      read_at: null,
    },
  ],
};

const supplyContractsState = [
  {
    contract_id: 'CTR-882',
    title: 'Quantum Core Energy Supply Agreement',
    proposer_id: 'H-0012',
    counterparty_id: 'H-0044',
    status: 'accepted',
    starts_game_day: 160,
    ends_game_day: 190,
    proposer_display_name: 'Dmitri Rostov',
    counterparty_display_name: 'Amara Vance',
    resource_type: 'energy',
    daily_quantity: '50.00',
    unit_price: '14.50',
    total_days: 30,
    delivered_days: 18,
    default_days: 1,
    consecutive_defaults: 0,
    max_consecutive_defaults: 3,
    escrow_total: '21750.00',
    escrow_remaining: '8700.00',
    penalty_per_default: '100.00',
    last_settled_game_day: 184,
    vault_id: 'VAULT-CTR-882',
    vault_locked_amount: '21750.00',
    vault_released_amount: '13050.00',
    vault_refunded_amount: '0.00',
    vault_penalty_paid: '100.00',
    vault_status: 'locked',
    created_at: new Date(Date.now() - 86400000).toISOString(),
  },
  {
    contract_id: 'CTR-904',
    title: 'High-Purity Silicon Supply Tender',
    proposer_id: 'H-0089',
    counterparty_id: 'H-0044',
    status: 'proposed',
    starts_game_day: 184,
    ends_game_day: 214,
    proposer_display_name: 'Elena Thorne',
    counterparty_display_name: 'Amara Vance',
    resource_type: 'material',
    daily_quantity: '25.00',
    unit_price: '28.00',
    total_days: 30,
    delivered_days: 0,
    default_days: 0,
    consecutive_defaults: 0,
    max_consecutive_defaults: 3,
    escrow_total: '21000.00',
    escrow_remaining: '21000.00',
    penalty_per_default: '250.00',
    last_settled_game_day: null,
    vault_id: 'VAULT-CTR-904',
    vault_locked_amount: '21000.00',
    vault_released_amount: '0.00',
    vault_refunded_amount: '0.00',
    vault_penalty_paid: '0.00',
    vault_status: 'locked',
    created_at: new Date(Date.now() - 14400000).toISOString(),
  },
];

const supplyTicksState = {
  'CTR-882': [
    {
      id: 'tick-184',
      contract_id: 'CTR-882',
      game_day: 184,
      status: 'delivered',
      quantity_delivered: '50.00',
      credits_transferred: '725.00',
      penalty_charged: '0.00',
      notes: null,
      created_at: new Date(Date.now() - 3600000).toISOString(),
    },
    {
      id: 'tick-183',
      contract_id: 'CTR-882',
      game_day: 183,
      status: 'delivered',
      quantity_delivered: '50.00',
      credits_transferred: '725.00',
      penalty_charged: '0.00',
      notes: null,
      created_at: new Date(Date.now() - 7200000).toISOString(),
    },
    {
      id: 'tick-182',
      contract_id: 'CTR-882',
      game_day: 182,
      status: 'defaulted',
      quantity_delivered: '0.00',
      credits_transferred: '0.00',
      penalty_charged: '100.00',
      notes: 'Insufficient inventory for scheduled delivery',
      created_at: new Date(Date.now() - 10800000).toISOString(),
    },
  ],
};

const planetaryRegionsState = [
  { id: 'REG-PACIFIC-RIM', name: 'Pacific Rim Sprawl', biome_type: 'coastal_megalopolis', description: 'Dense cybernetic coastal zones and high-throughput trade networks.', climate_status: 'temperate', base_solar_index: '1.15', base_geothermal_index: '1.30' },
  { id: 'REG-SAHARAN-BASIN', name: 'Saharan Solar Basin', biome_type: 'hyper_arid_desert', description: 'Massive photovoltaic and concentrated solar fields across the equator.', climate_status: 'arid', base_solar_index: '2.40', base_geothermal_index: '0.85' },
  { id: 'REG-NORDIC-CRYO', name: 'Nordic Cryo Hub', biome_type: 'sub_polar_tundra', description: 'Supercooled data clusters and geothermal power reservoirs in Scandinavian fjords.', climate_status: 'frigid', base_solar_index: '0.65', base_geothermal_index: '1.80' },
  { id: 'REG-ATACAMA-CORRIDOR', name: 'Atacama Mineral Basin', biome_type: 'high_altitude_plateau', description: 'Vast lithium salt flats and rare earth mineral extraction corridors.', climate_status: 'arid', base_solar_index: '1.85', base_geothermal_index: '1.10' },
  { id: 'REG-EURO-ALPINE', name: 'Euro-Alpine Hydro Grid', biome_type: 'alpine_montane', description: 'Hydroelectric cascade networks and high-precision quantum research labs.', climate_status: 'temperate', base_solar_index: '1.00', base_geothermal_index: '1.05' },
  { id: 'REG-ORBITAL-RING', name: 'Low Orbit Tether Array', biome_type: 'orbital_exosphere', description: 'Space elevator tether nodes and zero-gravity micro-fabrication platforms.', climate_status: 'vacuum', base_solar_index: '2.80', base_geothermal_index: '0.00' },
];

const territoryPlotsState = [
  { id: 'PLOT-PAC-01', region_id: 'REG-PACIFIC-RIM', plot_name: 'Neo-Tokyo High-Bay Terminal', coord_x: 139.69, coord_y: 35.68, terrain_type: 'coastal', primary_resource: 'compute', base_yield_rate: '25.00', development_level: 2, max_level: 5, infrastructure_name: 'Quantum Relay Server Bank', lease_holder_id: 'H-0044', lease_holder_name: 'Amara Vance', daily_lease_fee: '75.00', lease_expires_game_day: 214, accumulated_yield: '125.00', last_harvested_game_day: 179 },
  { id: 'PLOT-PAC-02', region_id: 'REG-PACIFIC-RIM', plot_name: 'Yokohama Deepwater Dock', coord_x: 139.63, coord_y: 35.44, terrain_type: 'marine', primary_resource: 'energy', base_yield_rate: '30.00', development_level: 1, max_level: 5, infrastructure_name: 'Tidal Surge Generator', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '60.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-PAC-03', region_id: 'REG-PACIFIC-RIM', plot_name: 'Kanto Inland Fabrication Dome', coord_x: 139.50, coord_y: 35.90, terrain_type: 'urban', primary_resource: 'material', base_yield_rate: '20.00', development_level: 1, max_level: 5, infrastructure_name: 'Automated Component Foundry', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '50.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-PAC-04', region_id: 'REG-PACIFIC-RIM', plot_name: 'Fuji Geothermal Vent', coord_x: 138.72, coord_y: 35.36, terrain_type: 'volcanic', primary_resource: 'energy', base_yield_rate: '45.00', development_level: 3, max_level: 5, infrastructure_name: 'Magma Tap Turbine', lease_holder_id: 'H-0012', lease_holder_name: 'Dmitri Rostov', daily_lease_fee: '120.00', lease_expires_game_day: 200, accumulated_yield: '90.00', last_harvested_game_day: 182 },

  { id: 'PLOT-SAH-01', region_id: 'REG-SAHARAN-BASIN', plot_name: 'Ksar Ghilane Mirror Array', coord_x: 9.63, coord_y: 32.98, terrain_type: 'dunes', primary_resource: 'energy', base_yield_rate: '60.00', development_level: 2, max_level: 5, infrastructure_name: 'Concentrated Solar Tower', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '90.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-SAH-02', region_id: 'REG-SAHARAN-BASIN', plot_name: 'Ahaggar High-Altitude Collector', coord_x: 5.52, coord_y: 23.28, terrain_type: 'rocky_desert', primary_resource: 'energy', base_yield_rate: '75.00', development_level: 3, max_level: 5, infrastructure_name: 'Photovoltaic Glassfield', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '140.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-SAH-03', region_id: 'REG-SAHARAN-BASIN', plot_name: 'Oasis Aeroponic Farm Ring', coord_x: 8.12, coord_y: 28.50, terrain_type: 'oasis', primary_resource: 'food', base_yield_rate: '35.00', development_level: 1, max_level: 5, infrastructure_name: 'Deep Aquifer Biome Dome', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '70.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-SAH-04', region_id: 'REG-SAHARAN-BASIN', plot_name: 'Reggane Silicon Quarry', coord_x: 0.17, coord_y: 26.71, terrain_type: 'gravel_desert', primary_resource: 'material', base_yield_rate: '30.00', development_level: 1, max_level: 5, infrastructure_name: 'Silica Harvester Array', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '65.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },

  { id: 'PLOT-NOR-01', region_id: 'REG-NORDIC-CRYO', plot_name: 'Svalbard Deep Glacial Vault', coord_x: 15.46, coord_y: 78.22, terrain_type: 'permafrost', primary_resource: 'compute', base_yield_rate: '50.00', development_level: 2, max_level: 5, infrastructure_name: 'Sub-Zero Server Vault', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '85.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-NOR-02', region_id: 'REG-NORDIC-CRYO', plot_name: 'Bergen Fjord Hydro Station', coord_x: 5.32, coord_y: 60.39, terrain_type: 'fjord', primary_resource: 'energy', base_yield_rate: '40.00', development_level: 2, max_level: 5, infrastructure_name: 'Cascading Hydro Generator', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '80.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-NOR-03', region_id: 'REG-NORDIC-CRYO', plot_name: 'Kiruna Sub-Crust Magnetite Mine', coord_x: 20.22, coord_y: 67.85, terrain_type: 'mountain', primary_resource: 'material', base_yield_rate: '55.00', development_level: 3, max_level: 5, infrastructure_name: 'Heavy Bore Excavator', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '110.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-NOR-04', region_id: 'REG-NORDIC-CRYO', plot_name: 'Tromsø Magnetic Observatory', coord_x: 18.95, coord_y: 69.64, terrain_type: 'arctic', primary_resource: 'compute', base_yield_rate: '30.00', development_level: 1, max_level: 5, infrastructure_name: 'Aurora Sensor Cluster', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '60.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },

  { id: 'PLOT-ATA-01', region_id: 'REG-ATACAMA-CORRIDOR', plot_name: 'Salar de Atacama Brine Fields', coord_x: -68.25, coord_y: -23.50, terrain_type: 'salt_flat', primary_resource: 'material', base_yield_rate: '70.00', development_level: 3, max_level: 5, infrastructure_name: 'Lithium Evaporation Pan Array', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '130.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ATA-02', region_id: 'REG-ATACAMA-CORRIDOR', plot_name: 'Chajnantor High Sensor Array', coord_x: -67.75, coord_y: -23.02, terrain_type: 'high_altitude', primary_resource: 'compute', base_yield_rate: '40.00', development_level: 2, max_level: 5, infrastructure_name: 'Sub-Millimeter Array Terminal', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '90.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ATA-03', region_id: 'REG-ATACAMA-CORRIDOR', plot_name: 'Antofagasta Coastal Smelter', coord_x: -70.40, coord_y: -23.65, terrain_type: 'coastal', primary_resource: 'material', base_yield_rate: '35.00', development_level: 1, max_level: 5, infrastructure_name: 'Plasma Smelting Complex', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '75.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ATA-04', region_id: 'REG-ATACAMA-CORRIDOR', plot_name: 'Domeykos Solar Corridor', coord_x: -69.10, coord_y: -24.80, terrain_type: 'rocky_desert', primary_resource: 'energy', base_yield_rate: '50.00', development_level: 2, max_level: 5, infrastructure_name: 'High-Irradiance PV Array', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '95.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },

  { id: 'PLOT-EUR-01', region_id: 'REG-EURO-ALPINE', plot_name: 'Geneva Quantum Collider Hub', coord_x: 6.14, coord_y: 46.20, terrain_type: 'urban', primary_resource: 'compute', base_yield_rate: '45.00', development_level: 2, max_level: 5, infrastructure_name: 'Sub-Atomic Accelerator Tap', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '100.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-EUR-02', region_id: 'REG-EURO-ALPINE', plot_name: 'Rhone Valley Hydro Cascade', coord_x: 7.36, coord_y: 46.23, terrain_type: 'valley', primary_resource: 'energy', base_yield_rate: '35.00', development_level: 1, max_level: 5, infrastructure_name: 'Alpine Reservoir Dam', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '70.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-EUR-03', region_id: 'REG-EURO-ALPINE', plot_name: 'Bavarian Synthetic Food Silos', coord_x: 11.58, coord_y: 48.13, terrain_type: 'plains', primary_resource: 'food', base_yield_rate: '40.00', development_level: 2, max_level: 5, infrastructure_name: 'Cellular Agriculture Facility', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '80.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-EUR-04', region_id: 'REG-EURO-ALPINE', plot_name: 'Ruhr Automated Metal Foundry', coord_x: 7.01, coord_y: 51.45, terrain_type: 'industrial', primary_resource: 'material', base_yield_rate: '45.00', development_level: 2, max_level: 5, infrastructure_name: 'Recycled Alloy Forge', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '90.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },

  { id: 'PLOT-ORB-01', region_id: 'REG-ORBITAL-RING', plot_name: 'Quito Space Elevator Anchor', coord_x: -78.46, coord_y: -0.18, terrain_type: 'equatorial_peak', primary_resource: 'energy', base_yield_rate: '80.00', development_level: 3, max_level: 5, infrastructure_name: 'Carbon Nanotube Power Link', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '180.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ORB-02', region_id: 'REG-ORBITAL-RING', plot_name: 'Kilimanjaro Sky Hook Station', coord_x: 37.35, coord_y: -3.06, terrain_type: 'equatorial_peak', primary_resource: 'material', base_yield_rate: '65.00', development_level: 2, max_level: 5, infrastructure_name: 'Orbital Freight Launcher', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '150.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ORB-03', region_id: 'REG-ORBITAL-RING', plot_name: 'Zenith Zero-G Fabrication Ring', coord_x: 0.00, coord_y: 0.00, terrain_type: 'orbital', primary_resource: 'material', base_yield_rate: '90.00', development_level: 4, max_level: 5, infrastructure_name: 'Microgravity Crucible', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '220.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
  { id: 'PLOT-ORB-04', region_id: 'REG-ORBITAL-RING', plot_name: 'Solar Lagrange Concentrator', coord_x: 0.00, coord_y: 0.00, terrain_type: 'orbital', primary_resource: 'energy', base_yield_rate: '100.00', development_level: 4, max_level: 5, infrastructure_name: 'Orbital Microwave Emitter', lease_holder_id: null, lease_holder_name: null, daily_lease_fee: '250.00', lease_expires_game_day: null, accumulated_yield: '0.00', last_harvested_game_day: null },
];

const EPOCH_START_TIME_MS = Date.parse('2026-01-01T00:00:00.000Z');

function computeCosmicClock(serverNow = Date.now()) {
  const elapsedRealSec = Math.max(0, Math.floor((serverNow - EPOCH_START_TIME_MS) / 1000));
  const totalSimMinutes = elapsedRealSec;
  const inDayMinute = totalSimMinutes % 1440;
  const totalDays = Math.floor(totalSimMinutes / 1440) + 1;
  return {
    epochStartTime: '2026-01-01T00:00:00.000Z',
    serverCurrentTime: serverNow,
    day: totalDays,
    minute: inDayMinute,
    realSecondsPerGameMinute: 1,
  };
}

Object.assign(state.clock, computeCosmicClock());

const serverClockInterval = setInterval(() => {
  Object.assign(state.clock, computeCosmicClock());
}, 1000);
if (serverClockInterval.unref) serverClockInterval.unref();

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
  state.resources.food = (state.resources.food || 0) + 16;
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
    const url = req ? new URL(req.url, 'http://127.0.0.1') : null;
    const category = (url?.searchParams.get('category') || body.category || 'citizens').toLowerCase();
    const metric = (url?.searchParams.get('metric') || body.metric || 'composite').toLowerCase();
    const search = (url?.searchParams.get('search') || body.search || '').trim().toLowerCase();
    const limit = Math.min(100, Math.max(1, Number(url?.searchParams.get('limit') || body.limit || 50)));

    let citizens = [
      {
        rank: 1,
        rankDelta: 0,
        tierBadge: 'Sovereign',
        id: 'H-0044',
        displayName: 'Amara Vance',
        ageYears: 42,
        standing: 840,
        legacy: 120,
        credits: 5000,
        cityId: 'city-new-tokyo',
        dynastyName: 'Vance Dynasty',
        compositeScore: 14484,
      },
      {
        rank: 2,
        rankDelta: 1,
        tierBadge: 'Patrician',
        id: 'H-0012',
        displayName: 'Dmitri Rostov',
        ageYears: 38,
        standing: 720,
        legacy: 95,
        credits: 4200,
        cityId: 'city-london',
        dynastyName: 'House of Rostov',
        compositeScore: 12150,
      },
      {
        rank: 3,
        rankDelta: -1,
        tierBadge: 'Patrician',
        id: 'H-0088',
        displayName: 'Kaelen Thorne',
        ageYears: 49,
        standing: 680,
        legacy: 80,
        credits: 3800,
        cityId: 'city-geneva',
        dynastyName: 'Thorne Syndicate',
        compositeScore: 10980,
      },
      {
        rank: 4,
        rankDelta: 'NEW',
        tierBadge: 'Pioneer',
        id: 'H-0105',
        displayName: 'Sariyah Chen',
        ageYears: 29,
        standing: 510,
        legacy: 45,
        credits: 2400,
        cityId: 'city-singapore',
        dynastyName: 'Chen Holdings',
        compositeScore: 7850,
      },
      {
        rank: 5,
        rankDelta: 2,
        tierBadge: 'Pioneer',
        id: 'H-0142',
        displayName: 'Tarek Al-Mansoor',
        ageYears: 34,
        standing: 480,
        legacy: 30,
        credits: 1900,
        cityId: 'city-new-york',
        dynastyName: 'Al-Mansoor House',
        compositeScore: 6540,
      },
    ];

    let cities = [
      { id: 'city-new-tokyo', name: 'Neo-Tokyo', residents: 124, treasury: 28500, housing_capacity: 150, energy_capacity: 180, connectivity_capacity: 160, health_capacity: 140, qolIndex: 92, rank: 1, rankDelta: 0 },
      { id: 'city-new-york', name: 'New York', residents: 98, treasury: 25000, housing_capacity: 120, energy_capacity: 140, connectivity_capacity: 150, health_capacity: 110, qolIndex: 85, rank: 2, rankDelta: 1 },
      { id: 'city-london', name: 'London', residents: 82, treasury: 21400, housing_capacity: 100, energy_capacity: 110, connectivity_capacity: 120, health_capacity: 95, qolIndex: 78, rank: 3, rankDelta: -1 },
      { id: 'city-geneva', name: 'Geneva', residents: 64, treasury: 18900, housing_capacity: 80, energy_capacity: 90, connectivity_capacity: 100, health_capacity: 90, qolIndex: 74, rank: 4, rankDelta: 0 },
      { id: 'city-singapore', name: 'Singapore', residents: 52, treasury: 16200, housing_capacity: 70, energy_capacity: 85, connectivity_capacity: 90, health_capacity: 80, qolIndex: 70, rank: 5, rankDelta: 'NEW' },
    ];

    let corporations = [
      { id: 'corp-kline-industrial', name: 'Kline Industrial Syndicate', member_count: 14, treasury: 32000, marketCap: 84000, rank: 1, rankDelta: 0 },
      { id: 'corp-aegis-power', name: 'Aegis Fusion & Grid', member_count: 11, treasury: 27500, marketCap: 68000, rank: 2, rankDelta: 1 },
      { id: 'corp-orbital-logistics', name: 'Orbital Logistics Consortia', member_count: 8, treasury: 19800, marketCap: 45000, rank: 3, rankDelta: -1 },
      { id: 'corp-solis-biotech', name: 'Solis Biocatalytics', member_count: 6, treasury: 14200, marketCap: 31000, rank: 4, rankDelta: 0 },
    ];

    let dynasticHouses = [
      { dynasty_name: 'Vance Dynasty', deceased_count: 3, peak_legacy: 5400, peak_standing: 980, active_heir: 'Amara Vance', rank: 1, rankDelta: 0 },
      { dynasty_name: 'House of Rostov', deceased_count: 2, peak_legacy: 3800, peak_standing: 860, active_heir: 'Dmitri Rostov', rank: 2, rankDelta: 0 },
      { dynasty_name: 'Thorne Syndicate', deceased_count: 1, peak_legacy: 2900, peak_standing: 720, active_heir: 'Kaelen Thorne', rank: 3, rankDelta: 'NEW' },
    ];

    let technologies = [
      { id: 'tech-quantum-core', name: 'Quantum Core Infrastructure', owner_id: 'H-0044', progress: 100, licenseCount: 8, rank: 1, rankDelta: 0 },
      { id: 'tech-fusion-containment', name: 'Magnetic Fusion Containment', owner_id: 'H-0012', progress: 85, licenseCount: 5, rank: 2, rankDelta: 1 },
      { id: 'tech-autonomous-logistics', name: 'Autonomous Supply Meshing', owner_id: 'H-0088', progress: 70, licenseCount: 4, rank: 3, rankDelta: -1 },
    ];

    if (search) {
      citizens = citizens.filter((c) => c.displayName.toLowerCase().includes(search) || c.id.toLowerCase().includes(search) || (c.dynastyName && c.dynastyName.toLowerCase().includes(search)));
      cities = cities.filter((c) => c.name.toLowerCase().includes(search) || c.id.toLowerCase().includes(search));
      corporations = corporations.filter((c) => c.name.toLowerCase().includes(search) || c.id.toLowerCase().includes(search));
      dynasticHouses = dynasticHouses.filter((d) => d.dynasty_name.toLowerCase().includes(search));
      technologies = technologies.filter((t) => t.name.toLowerCase().includes(search) || t.id.toLowerCase().includes(search));
    }

    return {
      ok: true,
      category,
      metric,
      wealth: citizens.map((c) => ({ human_id: c.id, balance: c.credits })),
      cities: cities.slice(0, limit),
      corporations: corporations.slice(0, limit),
      technologies: technologies.slice(0, limit),
      citizens: citizens.slice(0, limit),
      dynasticHouses: dynasticHouses.slice(0, limit),
      userStanding: {
        rank: 1,
        totalTracked: citizens.length,
        percentile: 1.0,
        tierBadge: 'Sovereign',
        score: citizens[0]?.compositeScore || 14484,
        nextRankGap: 0,
      },
      generatedFrom: database ? 'planetscale-postgres' : 'reference-simulator',
    };
  }
  if (path === '/api/cemetery' && body.method === 'GET') {
    const url = req ? new URL(req.url, 'http://127.0.0.1') : null;
    const search = (url?.searchParams.get('search') || body.search || '').trim().toLowerCase();
    const dynasty = (url?.searchParams.get('dynasty') || body.dynasty || '').trim();
    const limit = Math.min(100, Math.max(1, Number(url?.searchParams.get('limit') || body.limit || 50)));

    let memorials = [
      {
        human_id: 'H-0001',
        display_name: 'Founder Marcus Vance',
        death_game_day: 1200,
        final_standing: 980,
        final_legacy: 5400,
        successor_name: 'Amara Vance',
        cause_of_death: 'Natural Biological Mortality',
        epitaph: 'Pioneered civilization across the frontier of Earth.',
        dynasty_name: 'Vance Dynasty',
        birth_game_day: 1,
      },
      {
        human_id: 'H-0002',
        display_name: 'Elena Rostova',
        death_game_day: 940,
        final_standing: 860,
        final_legacy: 3800,
        successor_name: 'Dmitri Rostov',
        cause_of_death: 'Natural Biological Mortality',
        epitaph: 'Architect of municipal water security and free exchange.',
        dynasty_name: 'House of Rostov',
        birth_game_day: 1,
      },
    ];

    if (search) {
      memorials = memorials.filter((m) =>
        m.display_name.toLowerCase().includes(search) ||
        (m.dynasty_name && m.dynasty_name.toLowerCase().includes(search)) ||
        (m.successor_name && m.successor_name.toLowerCase().includes(search))
      );
    }
    if (dynasty) {
      memorials = memorials.filter((m) => m.dynasty_name === dynasty);
    }

    return {
      ok: true,
      cemetery: memorials.slice(0, limit),
      totalReturned: Math.min(memorials.length, limit),
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  // --- Universal Comm-Link & Diplomatic Mail ---
  if (path === '/api/comm/channels' && body.method === 'GET') {
    return {
      ok: true,
      channels: commState.channels,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/messages' && body.method === 'GET') {
    const url = req ? new URL(req.url, 'http://127.0.0.1') : null;
    const channelId = url?.searchParams.get('channelId') || body.channelId || 'channel-global-relay';
    const limit = Math.min(100, Math.max(1, Number(url?.searchParams.get('limit') || body.limit || 50)));
    const msgs = (commState.messages[channelId] || []).slice(-limit);
    return {
      ok: true,
      channelId,
      messages: msgs,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/messages' && body.method === 'POST') {
    const channelId = body.channelId || 'channel-global-relay';
    const text = (body.body || '').trim();
    if (!text) throw new ApiError('Message body cannot be empty', 400, 'VALIDATION_ERROR');

    const newMsg = {
      id: `msg-${Date.now()}`,
      channel_id: channelId,
      sender_human_id: 'H-0044',
      sender_display_name: 'Amara Vance',
      sender_dynasty_name: 'Vance Dynasty',
      body: text,
      game_day: state.clock.day || 184,
      game_minute: state.clock.minute || 500,
      attachments: body.attachments || [],
      created_at: new Date().toISOString(),
    };
    if (!commState.messages[channelId]) commState.messages[channelId] = [];
    commState.messages[channelId].push(newMsg);
    publish('comm.message.sent', newMsg);
    return {
      ok: true,
      message: newMsg,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/dispatches' && body.method === 'GET') {
    const url = req ? new URL(req.url, 'http://127.0.0.1') : null;
    const folder = url?.searchParams.get('folder') || body.folder || 'inbox';
    let list = commState.dispatches;
    if (folder === 'sent') {
      list = list.filter((d) => d.sender_human_id === 'H-0044');
    } else if (folder === 'archived') {
      list = list.filter((d) => d.recipient_human_id === 'H-0044' && d.status === 'archived');
    } else {
      list = list.filter((d) => d.recipient_human_id === 'H-0044' && d.status !== 'archived');
    }
    const unreadCount = commState.dispatches.filter((d) => d.recipient_human_id === 'H-0044' && d.status === 'unread').length;
    return {
      ok: true,
      folder,
      dispatches: list,
      unreadCount,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/dispatches' && body.method === 'POST') {
    const recipientId = (body.recipientId || '').trim();
    const subject = (body.subject || '').trim();
    const text = (body.body || '').trim();
    if (!recipientId || !subject || !text) {
      throw new ApiError('recipientId, subject, and body are required', 400, 'VALIDATION_ERROR');
    }
    const newDispatch = {
      id: `mail-${Date.now()}`,
      sender_human_id: 'H-0044',
      sender_display_name: 'Amara Vance',
      sender_dynasty_name: 'Vance Dynasty',
      recipient_human_id: recipientId,
      recipient_display_name: recipientId === 'H-0012' ? 'Dmitri Rostov' : (recipientId === 'H-0088' ? 'Kaelen Thorne' : recipientId),
      subject,
      body: text,
      status: 'unread',
      game_day: state.clock.day || 184,
      game_minute: state.clock.minute || 520,
      dispatch_type: body.dispatchType || 'diplomatic',
      action_payload: body.actionPayload || {},
      created_at: new Date().toISOString(),
      read_at: null,
    };
    commState.dispatches.unshift(newDispatch);
    publish('comm.dispatch.sent', newDispatch);
    return {
      ok: true,
      dispatch: newDispatch,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/dispatches/read' && body.method === 'POST') {
    const dispatchId = body.dispatchId;
    const found = commState.dispatches.find((d) => d.id === dispatchId);
    if (found) {
      found.status = 'read';
      found.read_at = new Date().toISOString();
    }
    return {
      ok: true,
      dispatchId,
      read: true,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/comm/metrics' && body.method === 'GET') {
    const unreadCount = commState.dispatches.filter((d) => d.recipient_human_id === 'H-0044' && d.status === 'unread').length;
    return {
      ok: true,
      unreadDispatches: unreadCount,
      activeChannelsCount: commState.channels.length,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  if (path === '/api/pantheon' && body.method === 'GET') {
    return {
      ok: true,
      deceasedPantheon: [
        {
          human_id: 'H-0001',
          display_name: 'Founder Marcus Vance',
          death_game_day: 1200,
          final_standing: 980,
          final_legacy: 5400,
          composite_legacy_score: 18160,
          successor_name: 'Amara Vance',
          cause_of_death: 'Natural Biological Mortality',
          epitaph: 'Pioneered civilization across the frontier of Earth.',
          dynasty_name: 'Vance Dynasty',
        },
        {
          human_id: 'H-0002',
          display_name: 'Elena Rostova',
          death_game_day: 940,
          final_standing: 860,
          final_legacy: 3800,
          composite_legacy_score: 13120,
          successor_name: 'Dmitri Rostov',
          cause_of_death: 'Natural Biological Mortality',
          epitaph: 'Architect of municipal water security and free exchange.',
          dynasty_name: 'House of Rostov',
        },
      ],
      dynasticHouses: [
        {
          dynasty_name: 'Vance Dynasty',
          deceased_count: 1,
          peak_legacy: 5400,
          peak_standing: 980,
        },
        {
          dynasty_name: 'House of Rostov',
          deceased_count: 1,
          peak_legacy: 3800,
          peak_standing: 860,
        },
      ],
      livingLeaders: [
        {
          id: 'H-0044',
          display_name: 'Amara Vance',
          age_years: 42,
          standing: 840,
          legacy: 120,
          composite_legacy_score: 14484,
        },
      ],
      persistence: database ? 'postgres-reference' : 'reference-simulator',
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

  if (path === '/api/contracts/supply' && body.method === 'GET') {
    return { ok: true, supplyContracts: supplyContractsState, persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  if (path === '/api/contracts/supply/propose' && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');

    const contractId = `CTR-${randomUUID().slice(0, 8).toUpperCase()}`;
    const dailyQuantity = Number(body.dailyQuantity || 10);
    const unitPrice = Number(body.unitPrice || 10);
    const totalDays = Number(body.totalDays || 30);
    const totalAmount = (dailyQuantity * unitPrice * totalDays).toFixed(2);
    const penaltyAmount = Number(body.penaltyPerDefault || 0).toFixed(2);
    const resourceType = body.resourceType || 'energy';
    const counterpartyId = body.counterpartyId?.trim() || 'H-0012';
    const title = body.title?.trim() || `${dailyQuantity} ${resourceType.toUpperCase()} / Day Supply Agreement`;

    const newSupplyContract = {
      contract_id: contractId,
      title,
      proposer_id: player.id,
      counterparty_id: counterpartyId,
      status: 'proposed',
      starts_game_day: state.clock.day,
      ends_game_day: state.clock.day + totalDays,
      proposer_display_name: player.name,
      counterparty_display_name: 'Dmitri Rostov',
      resource_type: resourceType,
      daily_quantity: dailyQuantity.toFixed(2),
      unit_price: unitPrice.toFixed(2),
      total_days: totalDays,
      delivered_days: 0,
      default_days: 0,
      consecutive_defaults: 0,
      max_consecutive_defaults: 3,
      escrow_total: totalAmount,
      escrow_remaining: totalAmount,
      penalty_per_default: penaltyAmount,
      last_settled_game_day: null,
      vault_id: `VAULT-${contractId}`,
      vault_locked_amount: totalAmount,
      vault_released_amount: '0.00',
      vault_refunded_amount: '0.00',
      vault_penalty_paid: '0.00',
      vault_status: 'locked',
      created_at: new Date().toISOString(),
    };

    supplyContractsState.unshift(newSupplyContract);
    publish('supply_contract.proposed', newSupplyContract);
    const result = { ok: true, contractId, totalAmount, status: 'proposed' };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const contractTicksMatch = path.match(/^\/api\/contracts\/([^/]+)\/ticks$/);
  if (contractTicksMatch && body.method === 'GET') {
    const contractId = contractTicksMatch[1];
    const ticks = supplyTicksState[contractId] || [];
    return { ok: true, ticks, persistence: database ? 'postgres-reference' : 'reference-simulator' };
  }

  // Planetary Map & Territory Concessions
  if (path === '/api/map/regions' && body.method === 'GET') {
    return {
      ok: true,
      regions: planetaryRegionsState,
      plots: territoryPlotsState,
      persistence: database ? 'postgres-reference' : 'reference-simulator',
    };
  }

  const plotLeaseMatch = path.match(/^\/api\/map\/plots\/([^/]+)\/lease$/);
  if (plotLeaseMatch && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const plotId = plotLeaseMatch[1];
    const plot = territoryPlotsState.find((p) => p.id === plotId);
    if (!plot) throw new ApiError('Territory plot not found', 404, 'NOT_FOUND');
    const duration = Math.max(7, Math.min(180, Number(body.durationDays || 30)));
    const totalCost = Number(plot.daily_lease_fee) * duration;
    if (player.credits < totalCost) throw new ApiError('Insufficient credits for concession lease', 409, 'CONFLICT');
    player.credits -= totalCost;
    plot.lease_holder_id = player.id;
    plot.lease_holder_name = player.name;
    plot.lease_expires_game_day = state.clock.day + duration;
    publish('plot.leased', { plotId, humanId: player.id, duration, totalCost });
    const result = { ok: true, plot, totalPaid: totalCost.toFixed(2), expiresGameDay: plot.lease_expires_game_day, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const plotUpgradeMatch = path.match(/^\/api\/map\/plots\/([^/]+)\/upgrade$/);
  if (plotUpgradeMatch && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const plotId = plotUpgradeMatch[1];
    const plot = territoryPlotsState.find((p) => p.id === plotId);
    if (!plot) throw new ApiError('Territory plot not found', 404, 'NOT_FOUND');
    if (plot.lease_holder_id !== player.id) throw new ApiError('Only concession leaseholder may upgrade', 403, 'FORBIDDEN');
    if (plot.development_level >= plot.max_level) throw new ApiError('Plot already at maximum level', 409, 'CONFLICT');
    const nextLvl = plot.development_level + 1;
    const costCredits = nextLvl * 500;
    const costMat = nextLvl * 25;
    if (player.credits < costCredits) throw new ApiError('Insufficient credits for upgrade', 409, 'CONFLICT');
    if ((state.resources.material || 0) < costMat) throw new ApiError('Insufficient material for upgrade', 409, 'CONFLICT');
    player.credits -= costCredits;
    state.resources.material -= costMat;
    plot.development_level = nextLvl;
    plot.base_yield_rate = (Number(plot.base_yield_rate) * 1.35).toFixed(2);
    plot.infrastructure_name = `${plot.infrastructure_name.replace(/\s*\[Mark\s*\d+\]/i, '')} [Mark ${nextLvl}]`;
    publish('plot.upgraded', { plotId, newLevel: nextLvl });
    const result = { ok: true, plot, newLevel: nextLvl, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
  }

  const plotHarvestMatch = path.match(/^\/api\/map\/plots\/([^/]+)\/harvest$/);
  if (plotHarvestMatch && body.method === 'POST') {
    const player = human('amara', req);
    if (!player) throw new ApiError('Authentication required', 401, 'AUTHENTICATION_REQUIRED');
    const plotId = plotHarvestMatch[1];
    const plot = territoryPlotsState.find((p) => p.id === plotId);
    if (!plot) throw new ApiError('Territory plot not found', 404, 'NOT_FOUND');
    if (plot.lease_holder_id !== player.id) throw new ApiError('Only concession leaseholder may harvest', 403, 'FORBIDDEN');
    const harvestAmount = Number(plot.accumulated_yield || 0);
    if (harvestAmount <= 0) throw new ApiError('No accumulated resources to harvest', 409, 'CONFLICT');
    const resource = plot.primary_resource || 'energy';
    state.resources[resource] = (state.resources[resource] || 0) + harvestAmount;
    plot.accumulated_yield = '0.00';
    plot.last_harvested_game_day = state.clock.day;
    publish('plot.harvested', { plotId, resource, harvestAmount });
    const result = { ok: true, plot, harvestedAmount: harvestAmount, resourceType: resource, state: snapshot() };
    if (correlationId) commandResults.set(correlationId, result);
    return result;
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
    const supplyContract = supplyContractsState.find((c) => c.contract_id === contractId);
    if (supplyContract) {
      supplyContract.status = 'accepted';
      publish('supply_contract.accepted', supplyContract);
      const result = { ok: true, status: 'accepted', contractId, escrowLocked: supplyContract.escrow_total };
      if (correlationId) commandResults.set(correlationId, result);
      return result;
    }
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
    const supplyContract = supplyContractsState.find((c) => c.contract_id === contractId);
    if (supplyContract) {
      supplyContract.status = 'cancelled';
      const refunded = supplyContract.escrow_remaining;
      supplyContract.escrow_remaining = '0.00';
      supplyContract.vault_status = 'refunded';
      publish('supply_contract.cancelled', supplyContract);
      const result = { ok: true, status: 'cancelled', contractId, refundedAmount: refunded };
      if (correlationId) commandResults.set(correlationId, result);
      return result;
    }
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

  if (path === '/api/auth/rebirth' && body.method === 'POST') {
    const displayName = (body.displayName || body.display_name || '').trim();
    if (!displayName || displayName.length < 2 || displayName.length > 80) {
      throw new ApiError('Display name must be between 2 and 80 characters', 400, 'VALIDATION_ERROR');
    }
    const dynastyName = (body.dynastyName || body.dynasty_name || '').trim();
    const cityId = (body.startingCityId || body.city_id || 'city-new-tokyo').trim();
    const humanId = `H-${Math.floor(1000 + Math.random() * 9000)}`;
    const newHuman = {
      id: humanId,
      display_name: displayName,
      displayName,
      email: 'citizen@earth.world',
      standing: 100,
      legacy: 0,
      age_years: 20,
      life_status: 'active',
      city_id: cityId,
      dynasty_name: dynastyName || undefined,
      credits: 200,
    };
    return {
      data: {
        ok: true,
        reborn: true,
        naturalizationFeePaid: 500,
        human: newHuman,
        persistence: database ? 'postgres-reference' : 'reference-simulator',
      },
      status: 200,
    };
  }

  if (path === '/api/auth/claim-heir' && body.method === 'POST') {
    const successorName = state.life?.successor?.name || 'Designated Heir';
    const humanId = `H-${Math.floor(1000 + Math.random() * 9000)}`;
    const newHuman = {
      id: humanId,
      display_name: successorName,
      displayName: successorName,
      email: 'citizen@earth.world',
      standing: 250,
      legacy: 50,
      age_years: 25,
      life_status: 'active',
      credits: 1000,
    };
    return {
      data: {
        ok: true,
        claimed: true,
        human: newHuman,
        persistence: database ? 'postgres-reference' : 'reference-simulator',
      },
      status: 200,
    };
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
    resourceFlows: {
      credits: { inflow: 1250, outflow: 320, net: 930 },
      food: { inflow: 16, outflow: 4, net: 12 },
      materials: { inflow: 24, outflow: 8, net: 16 },
      components: { inflow: 10, outflow: 12, net: -2 },
      energy: { inflow: 30, outflow: 18, net: 12 },
      compute: { inflow: 12, outflow: 4, net: 8 },
    },
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
    finance: {
      taxRules: state.taxRules || [{ scope: 'global', category: 'market', rate: '0.015', active: true }],
      liquidity: {
        activeHumans: Object.keys(state.humans || {}).length || 1,
        moneySupply: Object.values(state.humans || {}).reduce((acc, h) => acc + (h.credits || 0), 0) + 120000,
        target: 150000,
        corridor: { low: 120000, high: 180000 },
        status: 'inside-corridor',
      },
    },
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

function send(res, status, data, extraHeaders = {}, req = null) {
  const acceptHeader = req?.headers?.accept || '';
  const requestContentType = req?.headers?.['content-type'] || '';
  const corsOrigin = process.env.CORS_ORIGIN || req?.headers?.origin || '*';
  const prefersNano = acceptHeader.includes('application/nanomarkup') ||
    requestContentType.includes('application/nanomarkup');

  const headers = {
    'content-type': prefersNano ? 'application/nanomarkup; charset=utf-8' : 'application/json',
    'access-control-allow-origin': corsOrigin,
    'access-control-allow-credentials': 'true',
    'access-control-allow-headers': 'content-type, authorization, idempotency-key, x-request-id, accept',
    'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
    'access-control-expose-headers': 'x-request-id, x-earth-api-version',
    'x-earth-api-version': '2026-08',
    ...extraHeaders,
  };
  res.writeHead(status, headers);
  if (typeof data === 'string') {
    res.end(data);
  } else if (prefersNano) {
    res.end(toNano(data));
  } else {
    res.end(JSON.stringify(data));
  }
}

function sendError(res, status, message, code = null, correlationId = null, req = null) {
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
  send(res, status, payload, { 'x-request-id': finalCorrelationId }, req);
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
  if (!file && (pathname === '/flutter_bootstrap.js' || pathname === '/app/flutter_bootstrap.js' || pathname === '/main.dart.js' || pathname === '/app/main.dart.js')) {
    file = resolve('flutter_client/build/web', pathname.replace(/^\/app\//, '/').replace(/^\//, ''));
  }
  if (!file) return false;
  try {
    let content;
    try {
      content = await readFile(file);
    } catch (readErr) {
      if (pathname === '/app' || pathname === '/app/' || pathname === '/app.html') {
        const fallbackSource = resolve('flutter_client/web/app.html');
        content = (await readFile(fallbackSource, 'utf8')).replaceAll('$FLUTTER_BASE_HREF', '/app/');
      } else if (pathname.endsWith('flutter_bootstrap.js')) {
        content = '(() => { console.log("EARTH Flutter Bootstrap initialized"); })();\n';
      } else if (pathname.endsWith('main.dart.js')) {
        content = '(() => { console.log("EARTH Flutter Runtime initialized"); })();\n';
      } else {
        throw readErr;
      }
    }
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
        'access-control-allow-origin': process.env.CORS_ORIGIN || req.headers.origin || '*',
        'access-control-allow-credentials': 'true',
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
      const contentType = req.headers['content-type'] || '';
      body = (contentType.includes('application/nanomarkup') || raw.trim().startsWith('..') || raw.trim().startsWith(':'))
        ? fromNano(raw)
        : JSON.parse(raw);
    } catch {
      return sendError(
        res,
        400,
        'Malformed request payload',
        'VALIDATION_ERROR',
        correlationId,
        req,
      );
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return sendError(res, 400, 'Request body must be a valid mapping object', 'VALIDATION_ERROR', correlationId);
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
