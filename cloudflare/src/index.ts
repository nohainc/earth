import { DurableObject } from 'cloudflare:workers';

export class MarketCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      await ctx.storage.put('initialized', true);
    });
  }

  async submitCommand(payload: unknown): Promise<{ ok: true; coordinator: string }> {
    await this.ctx.storage.put('lastCommand', { payload, at: new Date().toISOString() });
    return { ok: true, coordinator: 'market' };
  }

  async snapshot(): Promise<unknown> {
    return this.ctx.storage.get('lastCommand');
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/edge/market') {
      const stub = env.MARKET_COORDINATOR.getByName('central-market');
      if (request.method === 'POST') return Response.json(await stub.submitCommand(await request.json()));
      return Response.json({ ok: true, coordinator: 'market', state: await stub.snapshot() });
    }
    if (url.pathname === '/api/world' && request.method === 'GET') {
      const [world, human, institutions, resources, business, technology, proposal, machines] = await Promise.all([
        env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind('H-0044').first(),
        env.DB.prepare('SELECT * FROM institutions').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind('H-0044').all(),
        env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind('B-1048').first(),
        env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind('TECH-001').first(),
        env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind('042').first(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind('H-0044').all(),
      ]);
      const institutionRows = institutions.results as Array<Record<string, unknown>>;
      const byKind = (kind: string) => institutionRows.find((item) => item.kind === kind) ?? {};
      const resourceMap = Object.fromEntries((resources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount]));
      return Response.json({
        clock: { day: world?.game_day ?? 184, minute: world?.game_minute ?? 0, realSecondsPerGameMinute: 1 },
        world: { health: world?.health ?? 68, batch: world?.market_batch_seconds ?? 498 },
        human: { id: human?.id, name: human?.display_name, credits: 18420, standing: human?.standing ?? 0, legacy: human?.legacy ?? 0, ageYears: human?.age_years ?? 31 },
        life: { generation: 1, successor: null, estatePeriodDays: 30 },
        institutions: { ouc: byKind('OUC'), corporation: byKind('CORPORATION'), city: byKind('CITY'), business: byKind('BUSINESS') },
        resources: resourceMap, business: business ?? {}, market: { products: {}, orders: [], lastSettlement: null },
        governance: { proposals: [{ ...(proposal ?? { id: '042', title: 'Components maintenance levy', status: 'open' }), votes: { support: 0, oppose: 0, uncast: 1 }, ballots: {} }] },
        technology: { research: technology ?? {} }, machines: machines.results, ledgerEntries: [], persistence: 'cloudflare-d1'
      });
    }
    if (url.pathname === '/api/day/advance' && request.method === 'POST') {
      const current = await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>();
      const day = (current?.game_day ?? 184) + 1;
      await env.DB.prepare('UPDATE world_state SET game_day = ?, game_minute = 0 WHERE id = ?').bind(day, 'WORLD').run();
      return Response.json({ ok: true, result: { day }, state: { clock: { day, minute: 0, realSecondsPerGameMinute: 1 }, world: { health: 68, batch: 498 }, human: { id: 'H-0044', name: 'Amara Kline', credits: 18420, standing: 742, legacy: 31, ageYears: 31 }, life: { generation: 1, successor: null, estatePeriodDays: 30 }, institutions: { ouc: {}, corporation: {}, city: {}, business: {} }, resources: {}, business: {}, market: { products: {}, orders: [], lastSettlement: null }, governance: { proposals: [] }, technology: { research: {} }, ledgerEntries: [], persistence: 'cloudflare-d1' } });
    }
    if (url.pathname === '/api/health') {
      const result = await env.DB.prepare('SELECT 1 AS ok').first<{ ok: number }>();
      return Response.json({ ok: result?.ok === 1, persistence: 'cloudflare-d1', environment: env.ENVIRONMENT });
    }
    if (url.pathname === '/api/audit' && request.method === 'GET') {
      const [balances, ledger, machines, succession] = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM account_balances WHERE balance < 0').first<{ invalid: number }>(),
        env.DB.prepare("SELECT COUNT(*) AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account").first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM machines WHERE condition < 0 OR condition > 100').first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS count FROM succession_plans WHERE human_id = ?').bind('H-0044').first<{ count: number }>(),
      ]);
      const checks = { balancesNonNegative: Number(balances?.invalid ?? 0) === 0, ledgerEntriesValid: Number(ledger?.invalid ?? 0) === 0, machineConditionsBounded: Number(machines?.invalid ?? 0) === 0, oneSuccessionPlanPerHuman: Number(succession?.count ?? 0) <= 1 };
      return Response.json({ ok: Object.values(checks).every(Boolean), checks, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/institutions' && request.method === 'GET') {
      const [community, city, corporation, membership, budgets] = await Promise.all([
        env.DB.prepare('SELECT * FROM communities ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM cities ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM corporations ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM memberships ORDER BY human_id').all(),
        env.DB.prepare('SELECT * FROM budgets ORDER BY game_day DESC').all(),
      ]);
      return Response.json({ community: community.results, city: city.results, corporation: corporation.results, membership: membership.results, budgets: budgets.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/cities/CITY-0084/budget' && request.method === 'POST') {
      const body = await request.json<{ category?: string; amount?: number }>();
      const category = body.category?.trim();
      const amount = Number(body.amount);
      if (!category || !Number.isFinite(amount) || amount < 0) return Response.json({ ok: false, error: 'A valid budget category and non-negative amount are required' }, { status: 400 });
      const city = await env.DB.prepare('SELECT treasury FROM cities WHERE id = ?').bind('CITY-0084').first<{ treasury: number }>();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      if (amount > Number(city.treasury)) return Response.json({ ok: false, error: 'Budget exceeds city treasury' }, { status: 400 });
      const id = `BUDGET-CITY-0084-${category}`;
      await env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?)) ON CONFLICT(id) DO UPDATE SET amount = excluded.amount, game_day = excluded.game_day').bind(id, 'CITY-0084', category, amount, 'WORLD').run();
      return Response.json({ ok: true, budget: await env.DB.prepare('SELECT * FROM budgets WHERE id = ?').bind(id).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/corporations/CORP-001/membership' && request.method === 'POST') {
      const body = await request.json<{ humanId?: string }>();
      const humanId = body.humanId || 'H-0044';
      const human = await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first();
      if (!human) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const existing = await env.DB.prepare('SELECT corporation_id FROM memberships WHERE human_id = ?').bind(humanId).first<{ corporation_id: string | null }>();
      if (existing?.corporation_id && existing.corporation_id !== 'CORP-001') return Response.json({ ok: false, error: 'Human already belongs to another corporation' }, { status: 409 });
      await env.DB.prepare('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES (?, ?, ?, (SELECT game_day FROM world_state WHERE id = ?)) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = excluded.city_id').bind(humanId, 'CORP-001', 'CITY-0084', 'WORLD').run();
      return Response.json({ ok: true, membership: await env.DB.prepare('SELECT * FROM memberships WHERE human_id = ?').bind(humanId).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/machines' && request.method === 'GET') {
      return Response.json({ machines: (await env.DB.prepare('SELECT * FROM machines ORDER BY id').all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology' && request.method === 'GET') {
      const [projects, patents, licenses] = await Promise.all([
        env.DB.prepare('SELECT * FROM research_projects ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM patents ORDER BY id').all(),
        env.DB.prepare('SELECT * FROM technology_licenses ORDER BY id').all(),
      ]);
      return Response.json({ projects: projects.results, patents: patents.results, licenses: licenses.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology/TECH-001/fund' && request.method === 'POST') {
      const body = await request.json<{ amount?: number }>();
      const amount = Number(body.amount ?? 240);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Funding amount must be positive' }, { status: 400 });
      const project = await env.DB.prepare('SELECT * FROM research_projects WHERE technology_id = ?').bind('TECH-001').first<Record<string, unknown>>();
      if (!project) return Response.json({ ok: false, error: 'Research project not found' }, { status: 404 });
      const progress = Math.min(100, Number(project.progress) + Math.min(10, amount / 60));
      await env.DB.batch([
        env.DB.prepare('UPDATE research_projects SET budget = budget + ?, progress = ? WHERE id = ?').bind(amount, progress, project.id),
        env.DB.prepare('UPDATE technologies SET progress = ? WHERE id = ?').bind(progress, 'TECH-001'),
      ]);
      return Response.json({ ok: true, project: await env.DB.prepare('SELECT * FROM research_projects WHERE id = ?').bind(project.id).first(), technology: await env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind('TECH-001').first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology/TECH-001/patent' && request.method === 'POST') {
      const project = await env.DB.prepare('SELECT * FROM research_projects WHERE technology_id = ?').bind('TECH-001').first<Record<string, unknown>>();
      if (!project || Number(project.progress) < 100) return Response.json({ ok: false, error: 'Research must reach 100% before patent grant' }, { status: 409 });
      const existing = await env.DB.prepare('SELECT * FROM patents WHERE technology_id = ? AND status = ?').bind('TECH-001', 'active').first();
      if (existing) return Response.json({ ok: true, patent: existing, persistence: 'cloudflare-d1' });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const patentId = `PAT-TECH-001`;
      await env.DB.prepare('INSERT INTO patents (id, technology_id, owner_id, granted_game_day, expiry_game_day) VALUES (?, ?, ?, ?, ?)').bind(patentId, 'TECH-001', project.owner_id, day, day + 3650).run();
      return Response.json({ ok: true, patent: await env.DB.prepare('SELECT * FROM patents WHERE id = ?').bind(patentId).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/technology/TECH-001/license' && request.method === 'POST') {
      const body = await request.json<{ licenseeId?: string; royaltyRate?: number }>();
      const licenseeId = body.licenseeId || 'H-0044';
      const royaltyRate = Number(body.royaltyRate ?? 0.05);
      const patent = await env.DB.prepare('SELECT * FROM patents WHERE technology_id = ? AND status = ?').bind('TECH-001', 'active').first<Record<string, unknown>>();
      if (!patent) return Response.json({ ok: false, error: 'An active patent is required' }, { status: 409 });
      if (!Number.isFinite(royaltyRate) || royaltyRate < 0 || royaltyRate > 1) return Response.json({ ok: false, error: 'Royalty rate must be between 0 and 1' }, { status: 400 });
      const licensee = await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(licenseeId).first();
      if (!licensee) return Response.json({ ok: false, error: 'Licensee not found' }, { status: 404 });
      const licenseId = `LIC-${patent.id}-${licenseeId}`;
      await env.DB.prepare('INSERT INTO technology_licenses (id, patent_id, licensor_id, licensee_id, royalty_rate) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET royalty_rate = excluded.royalty_rate, status = \'active\'').bind(licenseId, patent.id, patent.owner_id, licenseeId, royaltyRate).run();
      return Response.json({ ok: true, license: await env.DB.prepare('SELECT * FROM technology_licenses WHERE id = ?').bind(licenseId).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/finance' && request.method === 'GET') {
      const [accounts, rules] = await Promise.all([env.DB.prepare('SELECT * FROM account_balances ORDER BY account_id').all(), env.DB.prepare('SELECT * FROM tax_rules WHERE active = 1 ORDER BY id').all()]);
      return Response.json({ accounts: accounts.results, taxRules: rules.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/taxes/settle' && request.method === 'POST') {
      const body = await request.json<{ accountId?: string; taxableAmount?: number }>();
      const accountId = body.accountId || 'account-amara';
      const taxableAmount = Number(body.taxableAmount);
      if (!Number.isFinite(taxableAmount) || taxableAmount <= 0) return Response.json({ ok: false, error: 'Taxable amount must be positive' }, { status: 400 });
      const rule = await env.DB.prepare('SELECT * FROM tax_rules WHERE id = ? AND active = 1').bind('TAX-OUC-BASIC').first<{ rate: number; version: number }>();
      const account = await env.DB.prepare('SELECT * FROM account_balances WHERE account_id = ?').bind(accountId).first<{ owner_id: string; balance: number }>();
      if (!rule || !account) return Response.json({ ok: false, error: 'Tax rule or account not found' }, { status: 404 });
      const amount = Math.round(taxableAmount * Number(rule.rate) * 100) / 100;
      if (Number(account.balance) < amount) return Response.json({ ok: false, error: 'Insufficient Credits for tax settlement' }, { status: 409 });
      const correlationId = crypto.randomUUID();
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ?').bind(amount, accountId),
        env.DB.prepare('UPDATE account_balances SET balance = balance + ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, gameDay, accountId, 'account-ouc-treasury', amount, 'CREDIT', 'tax_settlement', accountId, `tax-v${rule.version}`, correlationId),
      ]);
      return Response.json({ ok: true, amount, ruleVersion: rule.version, correlationId, accounts: (await env.DB.prepare('SELECT * FROM account_balances WHERE account_id IN (?, ?)').bind(accountId, 'account-ouc-treasury').all()).results, persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'GET') {
      return Response.json({ successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind('H-0044').first(), persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'POST') {
      const body = await request.json<{ name?: string; estatePeriodDays?: number }>();
      const successorName = body.name?.trim();
      const estatePeriodDays = Number(body.estatePeriodDays ?? 30);
      if (!successorName || successorName.length < 2) return Response.json({ ok: false, error: 'Successor name is required' }, { status: 400 });
      if (!Number.isInteger(estatePeriodDays) || estatePeriodDays < 7 || estatePeriodDays > 90) return Response.json({ ok: false, error: 'Estate period must be between 7 and 90 days' }, { status: 400 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      await env.DB.prepare('INSERT INTO succession_plans (human_id, successor_name, registered_game_day, estate_period_days) VALUES (?, ?, ?, ?) ON CONFLICT(human_id) DO UPDATE SET successor_name = excluded.successor_name, registered_game_day = excluded.registered_game_day, estate_period_days = excluded.estate_period_days').bind('H-0044', successorName, day, estatePeriodDays).run();
      return Response.json({ ok: true, successor: await env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind('H-0044').first(), persistence: 'cloudflare-d1' });
    }
    const maintenanceMatch = url.pathname.match(/^\/api\/machines\/([^/]+)\/maintenance$/);
    if (maintenanceMatch && request.method === 'POST') {
      const machineId = maintenanceMatch[1];
      const machine = await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first<Record<string, unknown>>();
      if (!machine) return Response.json({ ok: false, error: 'Machine not found' }, { status: 404 });
      const body = await request.json<{ amount?: number }>();
      const amount = Number(body.amount ?? 10);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Maintenance amount must be positive' }, { status: 400 });
      const before = Number(machine.condition);
      const after = Math.min(100, before + amount * 0.8);
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const eventId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE machines SET condition = ?, maintenance_due = MAX(0, maintenance_due - ?) WHERE id = ?').bind(after, amount, machineId),
        env.DB.prepare('INSERT INTO maintenance_events (id, machine_id, owner_id, resource, amount, condition_before, condition_after, game_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?)').bind(eventId, machineId, machine.owner_id, 'components', amount, before, after, gameDay),
      ]);
      return Response.json({ ok: true, machine: await env.DB.prepare('SELECT * FROM machines WHERE id = ?').bind(machineId).first(), eventId, persistence: 'cloudflare-d1' });
    }
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, _env: Env, _ctx: ExecutionContext): Promise<void> {
    // Background settlement/aging work will be connected to the authoritative command bus.
  }
};
