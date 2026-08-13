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

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/edge/market') {
      const stub = env.MARKET_COORDINATOR.getByName('central-market');
      if (request.method === 'POST') return Response.json(await stub.submitCommand(await request.json()));
      return Response.json({ ok: true, coordinator: 'market', state: await stub.snapshot() });
    }
    if (url.pathname === '/api/world' && request.method === 'GET') {
      const [world, human, institutions, resources, business, technology, proposal, machines, account, ballots, succession, prices, ledger, cityMetrics, corporationMetrics] = await Promise.all([
        env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind('H-0044').first(),
        env.DB.prepare('SELECT * FROM institutions').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind('H-0044').all(),
        env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind('B-1048').first(),
        env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind('TECH-001').first(),
        env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind('042').first(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind('H-0044').all(),
        env.DB.prepare('SELECT balance FROM account_balances WHERE account_id = ?').bind('account-amara').first<{ balance: number }>(),
        env.DB.prepare('SELECT choice, COUNT(*) AS count FROM ballots WHERE proposal_id = ? GROUP BY choice').bind('042').all(),
        env.DB.prepare('SELECT * FROM succession_plans WHERE human_id = ?').bind('H-0044').first(),
        env.DB.prepare('SELECT * FROM market_prices ORDER BY product').all(),
        env.DB.prepare('SELECT * FROM ledger_entries ORDER BY created_at DESC LIMIT 25').all(),
        env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind('CITY-0084').first(),
        env.DB.prepare('SELECT * FROM corporations WHERE id = ?').bind('CORP-001').first(),
      ]);
      const institutionRows = institutions.results as Array<Record<string, unknown>>;
      const byKind = (kind: string) => institutionRows.find((item) => item.kind === kind) ?? {};
      const resourceMap = Object.fromEntries((resources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount]));
      const voteCounts = Object.fromEntries((ballots.results as Array<Record<string, unknown>>).map((item) => [item.choice, Number(item.count)]));
      const marketProducts = Object.fromEntries((prices.results as Array<Record<string, unknown>>).map((item) => [item.product, { price: item.price, supply: item.supply, demand: item.demand }]));
      const rankings = await Promise.all([
        env.DB.prepare('SELECT id, residents, treasury, housing_capacity, energy_capacity FROM cities ORDER BY treasury DESC LIMIT 10').all(),
        env.DB.prepare('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC LIMIT 10').all(),
      ]);
      const [book, trades] = await Promise.all([
        env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all(),
        env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all(),
      ]);
      const communities = await env.DB.prepare('SELECT id, name, status FROM communities ORDER BY name LIMIT 20').all();
      const technologyRegistry = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS count FROM patents WHERE technology_id = ? AND status = ?').bind('TECH-001', 'active').first(),
        env.DB.prepare('SELECT COUNT(*) AS count FROM technology_licenses WHERE patent_id = ? AND status = ?').bind('PAT-TECH-001', 'active').first(),
      ]);
      const finance = await env.DB.prepare('SELECT scope, category, rate, version FROM tax_rules WHERE active = 1 ORDER BY id').all();
      const audit = await Promise.all([
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM account_balances WHERE balance < 0').first<{ invalid: number }>(),
        env.DB.prepare("SELECT COUNT(*) AS invalid FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account").first<{ invalid: number }>(),
        env.DB.prepare('SELECT COUNT(*) AS invalid FROM machines WHERE condition < 0 OR condition > 100').first<{ invalid: number }>(),
      ]);
      return Response.json({
        clock: { day: world?.game_day ?? 184, minute: world?.game_minute ?? 0, realSecondsPerGameMinute: 1 },
        world: { health: world?.health ?? 68, batch: world?.market_batch_seconds ?? 498 },
        human: { id: human?.id, name: human?.display_name, credits: account?.balance ?? 0, standing: human?.standing ?? 0, legacy: human?.legacy ?? 0, ageYears: human?.age_years ?? 31 },
        life: { generation: 1, successor: succession ?? null, estatePeriodDays: succession?.estate_period_days ?? 30 },
        institutions: { ouc: byKind('OUC'), corporation: { ...byKind('CORPORATION'), ...corporationMetrics }, city: { ...byKind('CITY'), ...cityMetrics }, business: byKind('BUSINESS') },
        resources: resourceMap, business: business ?? {}, market: { products: marketProducts, book: book.results, trades: trades.results, orders: [], lastSettlement: null },
        governance: { proposals: [{ ...(proposal ?? { id: '042', title: 'Components maintenance levy', status: 'open' }), votes: { support: voteCounts.support ?? 0, oppose: voteCounts.oppose ?? 0, abstain: voteCounts.abstain ?? 0 }, ballots: {} }] },
        technology: { research: technology ?? {}, activePatents: Number(technologyRegistry[0]?.count ?? 0), activeLicenses: Number(technologyRegistry[1]?.count ?? 0) }, machines: machines.results, ledgerEntries: ledger.results,
        publicActivity: [{ type: 'world_clock', day: world?.game_day ?? 184 }, { type: 'research_progress', progress: technology?.progress ?? 0 }, { type: 'market_cycle', batch: world?.market_batch_seconds ?? 498 }],
        rankings: { cities: rankings[0].results, corporations: rankings[1].results },
        communities: communities.results,
        audit: { balancesNonNegative: Number(audit[0]?.invalid ?? 0) === 0, ledgerEntriesValid: Number(audit[1]?.invalid ?? 0) === 0, machineConditionsBounded: Number(audit[2]?.invalid ?? 0) === 0 },
        finance: { taxRules: finance.results },
        persistence: 'cloudflare-d1'
      });
    }
    if (url.pathname === '/api/day/advance' && request.method === 'POST') {
      const current = await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>();
      const day = (current?.game_day ?? 184) + 1;
      await env.DB.batch([
        env.DB.prepare('UPDATE world_state SET game_day = ?, game_minute = 0 WHERE id = ?').bind(day, 'WORLD'),
        env.DB.prepare('UPDATE machines SET condition = MAX(0, condition - MAX(0.1, utilization * 0.01)), maintenance_due = maintenance_due + MAX(1, utilization * 0.5)'),
        ...(day % 365 === 0 ? [env.DB.prepare('UPDATE humans SET age_years = age_years + 1 WHERE id = ?').bind('H-0044')] : []),
      ]);
      const [updatedHuman, updatedAccount, updatedMachines, updatedResources, updatedBusiness, updatedTechnology] = await Promise.all([
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind('H-0044').first(),
        env.DB.prepare('SELECT balance FROM account_balances WHERE account_id = ?').bind('account-amara').first<{ balance: number }>(),
        env.DB.prepare('SELECT * FROM machines WHERE owner_id = ? ORDER BY id').bind('H-0044').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind('H-0044').all(),
        env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind('B-1048').first(),
        env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind('TECH-001').first(),
      ]);
      return Response.json({ ok: true, result: { day }, state: { clock: { day, minute: 0, realSecondsPerGameMinute: 1 }, world: { health: 68, batch: 498 }, human: { id: updatedHuman?.id, name: updatedHuman?.display_name, credits: updatedAccount?.balance ?? 0, standing: updatedHuman?.standing ?? 0, legacy: updatedHuman?.legacy ?? 0, ageYears: updatedHuman?.age_years ?? 31 }, life: { generation: 1, successor: null, estatePeriodDays: 30 }, institutions: {}, resources: Object.fromEntries((updatedResources.results as Array<Record<string, unknown>>).map((item) => [item.resource, item.amount])), business: updatedBusiness ?? {}, market: { products: {}, orders: [], lastSettlement: null }, governance: { proposals: [] }, technology: { research: updatedTechnology ?? {} }, machines: updatedMachines.results, ledgerEntries: [], persistence: 'cloudflare-d1' } });
    }
    if (url.pathname === '/api/health') {
      const result = await env.DB.prepare('SELECT 1 AS ok').first<{ ok: number }>();
      return Response.json({ ok: result?.ok === 1, persistence: 'cloudflare-d1', environment: env.ENVIRONMENT });
    }
    if (url.pathname === '/api/world/activity' && request.method === 'GET') {
      const [world, technology] = await Promise.all([
        env.DB.prepare('SELECT game_day, market_batch_seconds FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT progress FROM technologies WHERE id = ?').bind('TECH-001').first(),
      ]);
      return Response.json({ activity: [{ type: 'world_clock', day: world?.game_day ?? 184 }, { type: 'research_progress', progress: technology?.progress ?? 0 }, { type: 'market_cycle', batch: world?.market_batch_seconds ?? 498 }], persistence: 'cloudflare-d1' });
    }
    if ((url.pathname === '/api/audit' || url.pathname === '/api/world/audit') && request.method === 'GET') {
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
    if (url.pathname === '/api/communities' && request.method === 'GET') {
      return Response.json({ communities: (await env.DB.prepare('SELECT * FROM communities ORDER BY id').all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/communities' && request.method === 'POST') {
      const body = await request.json<{ name?: string; founderId?: string }>();
      const name = body.name?.trim();
      const founderId = body.founderId || 'H-0044';
      if (!name || name.length < 3 || name.length > 80) return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(founderId).first())) return Response.json({ ok: false, error: 'Founder not found' }, { status: 404 });
      const communityId = `COMM-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
      await env.DB.prepare('INSERT INTO communities (id, name, founder_id, shared_credits) VALUES (?, ?, ?, 0)').bind(communityId, name, founderId).run();
      return Response.json({ ok: true, community: await env.DB.prepare('SELECT * FROM communities WHERE id = ?').bind(communityId).first(), persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/rankings' && request.method === 'GET') {
      const [wealth, cities, corporations, technologies] = await Promise.all([
        env.DB.prepare('SELECT owner_id AS human_id, balance FROM account_balances WHERE currency = ? ORDER BY balance DESC').bind('CREDIT').all(),
        env.DB.prepare('SELECT id, residents, treasury, housing_capacity, energy_capacity, connectivity_capacity, health_capacity FROM cities ORDER BY treasury DESC').all(),
        env.DB.prepare('SELECT id, member_count, treasury FROM corporations ORDER BY member_count DESC, treasury DESC').all(),
        env.DB.prepare('SELECT id, name, owner_id, progress FROM technologies ORDER BY progress DESC').all(),
      ]);
      return Response.json({ wealth: wealth.results, cities: cities.results, corporations: corporations.results, technologies: technologies.results, generatedFrom: 'cloudflare-d1', persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/cities' && request.method === 'GET') {
      const cities = await env.DB.prepare('SELECT * FROM cities ORDER BY id').all();
      return Response.json({ cities: cities.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/corporations' && request.method === 'GET') {
      const corporations = await env.DB.prepare('SELECT * FROM corporations ORDER BY id').all();
      return Response.json({ corporations: corporations.results, persistence: 'cloudflare-d1' });
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
      await env.DB.batch([
        env.DB.prepare("UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = 'CORP-001') WHERE id = 'CORP-001'"),
        env.DB.prepare("UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = 'CITY-0084') WHERE id = 'CITY-0084'"),
      ]);
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
    if (url.pathname === '/api/finance/public-spending' && request.method === 'POST') {
      const body = await request.json<{ cityId?: string; category?: string; amount?: number }>();
      const cityId = body.cityId || 'CITY-0084';
      const category = body.category?.trim() || 'public-services';
      const amount = Number(body.amount);
      if (!Number.isFinite(amount) || amount <= 0) return Response.json({ ok: false, error: 'Public spending amount must be positive' }, { status: 400 });
      const treasury = await env.DB.prepare('SELECT balance FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first<{ balance: number }>();
      const city = await env.DB.prepare('SELECT id FROM cities WHERE id = ?').bind(cityId).first();
      if (!city) return Response.json({ ok: false, error: 'City not found' }, { status: 404 });
      if (!treasury || Number(treasury.balance) < amount) return Response.json({ ok: false, error: 'OUC treasury cannot fund this spending' }, { status: 409 });
      const day = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const correlationId = crypto.randomUUID();
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE account_id = ?').bind(amount, 'account-ouc-treasury'),
        env.DB.prepare('UPDATE cities SET treasury = treasury + ? WHERE id = ?').bind(amount, cityId),
        env.DB.prepare('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET amount = amount + excluded.amount, game_day = excluded.game_day').bind(`SPEND-${cityId}-${category}`, cityId, category, amount, day),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(correlationId, day, 'account-ouc-treasury', cityId, amount, 'CREDIT', 'public_spending', cityId, 'finance-v1', correlationId),
      ]);
      return Response.json({ ok: true, amount, city: await env.DB.prepare('SELECT * FROM cities WHERE id = ?').bind(cityId).first(), treasury: await env.DB.prepare('SELECT * FROM account_balances WHERE account_id = ?').bind('account-ouc-treasury').first(), correlationId, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/book' && request.method === 'GET') {
      const rows = await env.DB.prepare("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product").all();
      const trades = await env.DB.prepare('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product').all();
      return Response.json({ book: rows.results, trades: trades.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'GET') {
      const product = url.searchParams.get('product');
      const query = product ? env.DB.prepare('SELECT * FROM market_orders WHERE product = ? ORDER BY created_at DESC LIMIT 100').bind(product) : env.DB.prepare('SELECT * FROM market_orders ORDER BY created_at DESC LIMIT 100');
      return Response.json({ orders: (await query.all()).results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/orders' && request.method === 'POST') {
      const body = await request.json<{ humanId?: string; product?: string; quantity?: number; limitPrice?: number }>();
      const humanId = body.humanId || 'H-0044';
      const product = body.product;
      const quantity = Number(body.quantity);
      const limitPrice = Number(body.limitPrice);
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      const orderId = crypto.randomUUID();
      await env.DB.prepare('INSERT INTO market_orders (id, human_id, product, quantity, limit_price) VALUES (?, ?, ?, ?, ?)').bind(orderId, humanId, product, quantity, limitPrice).run();
      const coordinator = env.MARKET_COORDINATOR.getByName(`market-${product}`);
      const coordination = await coordinator.submitCommand({ type: 'order.submitted', orderId, product, quantity });
      return Response.json({ ok: true, order: await env.DB.prepare('SELECT * FROM market_orders WHERE id = ?').bind(orderId).first(), coordination, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/market/settle' && request.method === 'POST') {
      const body = await request.json<{ product?: string }>();
      const product = body.product;
      if (!['material', 'components', 'energy', 'compute'].includes(product ?? '')) return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
      const price = await env.DB.prepare('SELECT * FROM market_prices WHERE product = ?').bind(product).first<{ price: number; supply: number }>();
      const order = await env.DB.prepare("SELECT * FROM market_orders WHERE product = ? AND status IN ('open','partial') ORDER BY created_at ASC LIMIT 1").bind(product).first<Record<string, unknown>>();
      if (!price || !order) return Response.json({ ok: true, filled: false, reason: 'No eligible order or price', persistence: 'cloudflare-d1' });
      const remaining = Number(order.quantity) - Number(order.filled_quantity);
      const fill = Math.min(remaining, Number(price.supply));
      if (fill <= 0) return Response.json({ ok: true, filled: false, reason: 'No available supply', persistence: 'cloudflare-d1' });
      const account = await env.DB.prepare('SELECT balance FROM account_balances WHERE owner_id = ?').bind(order.human_id).first<{ balance: number }>();
      const total = Math.round(fill * Number(price.price) * 100) / 100;
      if (!account || Number(account.balance) < total) {
        await env.DB.prepare("UPDATE market_orders SET status = 'rejected' WHERE id = ?").bind(order.id).run();
        return Response.json({ ok: false, error: 'Insufficient Credits', orderId: order.id }, { status: 409 });
      }
      const gameDay = (await env.DB.prepare('SELECT game_day FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number }>())?.game_day ?? 184;
      const tradeId = crypto.randomUUID();
      const newFilled = Number(order.filled_quantity) + fill;
      const status = newFilled >= Number(order.quantity) ? 'filled' : 'partial';
      await env.DB.batch([
        env.DB.prepare('UPDATE account_balances SET balance = balance - ? WHERE owner_id = ?').bind(total, order.human_id),
        env.DB.prepare('INSERT INTO resource_balances (owner_id, resource, amount) VALUES (?, ?, ?) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = amount + excluded.amount').bind(order.human_id, product, fill),
        env.DB.prepare('UPDATE market_orders SET filled_quantity = ?, status = ? WHERE id = ?').bind(newFilled, status, order.id),
        env.DB.prepare('UPDATE market_prices SET supply = supply - ?, demand = MAX(0, demand - ?), game_day = ? WHERE product = ?').bind(fill, fill, gameDay, product),
        env.DB.prepare('INSERT INTO market_trades (id, order_id, product, quantity, clearing_price, game_day) VALUES (?, ?, ?, ?, ?, ?)').bind(tradeId, order.id, product, fill, price.price, gameDay),
        env.DB.prepare('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)').bind(tradeId, gameDay, order.human_id, 'central-market', total, 'CREDIT', 'market_trade', order.id, 'market-v1', tradeId),
      ]);
      return Response.json({ ok: true, filled: true, orderId: order.id, tradeId, product, quantity: fill, clearingPrice: price.price, total, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/governance/proposals' && request.method === 'GET') {
      const proposals = await env.DB.prepare('SELECT * FROM proposals ORDER BY closes_at ASC').all();
      const ballots = await env.DB.prepare('SELECT proposal_id, choice, COUNT(*) AS count FROM ballots GROUP BY proposal_id, choice').all();
      return Response.json({ proposals: proposals.results, voteCounts: ballots.results, persistence: 'cloudflare-d1' });
    }
    const voteMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
    if (voteMatch && request.method === 'POST') {
      const proposalId = voteMatch[1];
      const body = await request.json<{ humanId?: string; vote?: string }>();
      const humanId = body.humanId || 'H-0044';
      if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
      if (!(await env.DB.prepare('SELECT id FROM proposals WHERE id = ? AND status = ?').bind(proposalId, 'open').first())) return Response.json({ ok: false, error: 'Open proposal not found' }, { status: 404 });
      if (!(await env.DB.prepare('SELECT id FROM humans WHERE id = ?').bind(humanId).first())) return Response.json({ ok: false, error: 'Human not found' }, { status: 404 });
      try {
        await env.DB.prepare('INSERT INTO ballots (proposal_id, human_id, choice, weight) VALUES (?, ?, ?, 1)').bind(proposalId, humanId, body.vote).run();
      } catch (_error) {
        return Response.json({ ok: false, error: 'Ballot already recorded' }, { status: 409 });
      }
      const counts = await env.DB.prepare('SELECT choice, COUNT(*) AS count FROM ballots WHERE proposal_id = ? GROUP BY choice').bind(proposalId).all();
      return Response.json({ ok: true, proposalId, humanId, vote: body.vote, counts: counts.results, persistence: 'cloudflare-d1' });
    }
    if (url.pathname === '/api/businesses/kline-works/policy' && request.method === 'POST') {
      const body = await request.json<{ policy?: string }>();
      if (!['reliability', 'margin', 'capacity'].includes(body.policy ?? '')) return Response.json({ ok: false, error: 'Unknown business policy' }, { status: 400 });
      await env.DB.prepare('UPDATE businesses SET policy = ? WHERE id = ?').bind(body.policy, 'B-1048').run();
      return Response.json({ ok: true, policy: body.policy, business: await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind('B-1048').first(), persistence: 'cloudflare-d1' });
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
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    const world = await env.DB.prepare('SELECT game_day, game_minute FROM world_state WHERE id = ?').bind('WORLD').first<{ game_day: number; game_minute: number }>();
    const minute = Number(world?.game_minute ?? 0) + 5;
    const day = Number(world?.game_day ?? 184) + (minute >= 1440 ? 1 : 0);
    await env.DB.batch([
      env.DB.prepare('UPDATE world_state SET game_day = ?, game_minute = ? WHERE id = ?').bind(day, minute % 1440, 'WORLD'),
      env.DB.prepare('UPDATE machines SET condition = MAX(0, condition - MAX(0.05, utilization * 0.005)), maintenance_due = maintenance_due + MAX(1, utilization * 0.25)'),
      env.DB.prepare("UPDATE market_prices SET price = MAX(1, ROUND(price * (1 + MIN(0.05, MAX(-0.05, (demand - supply) / MAX(1, supply + demand)))) , 2)), game_day = ?").bind(day),
      env.DB.prepare("UPDATE world_state SET health = CAST(MAX(0, MIN(100, (SELECT COALESCE(AVG(condition), 68) FROM machines))) AS INTEGER) WHERE id = 'WORLD'"),
      env.DB.prepare("UPDATE cities SET health_capacity = CAST(MAX(0, MIN(100, (SELECT health FROM world_state WHERE id = 'WORLD'))) AS INTEGER)"),
      ...(minute >= 1440 ? [
        env.DB.prepare("UPDATE research_projects SET progress = MIN(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'"),
        env.DB.prepare("UPDATE technologies SET progress = MIN(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)"),
      ] : []),
      ...(day % 365 === 0 && minute < 5 ? [env.DB.prepare('UPDATE humans SET age_years = age_years + 1')]: []),
    ]);
  }
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: {
        'Access-Control-Allow-Origin': request.headers.get('Origin') ?? '*',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '86400',
      } });
    }
    const response = await worker.fetch(request, env, ctx);
    const headers = new Headers(response.headers);
    const origin = request.headers.get('Origin');
    if (origin === 'https://earth-client.pages.dev' || origin?.endsWith('.earth-client.pages.dev')) {
      headers.set('Access-Control-Allow-Origin', origin);
      headers.set('Vary', 'Origin');
    }
    headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    return worker.scheduled(event, env, ctx);
  },
};
