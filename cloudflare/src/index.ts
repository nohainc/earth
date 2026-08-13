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
      const [world, human, institutions, resources, business, technology, proposal] = await Promise.all([
        env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first(),
        env.DB.prepare('SELECT * FROM humans WHERE id = ?').bind('H-0044').first(),
        env.DB.prepare('SELECT * FROM institutions').all(),
        env.DB.prepare('SELECT resource, amount FROM resource_balances WHERE owner_id = ?').bind('H-0044').all(),
        env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind('B-1048').first(),
        env.DB.prepare('SELECT * FROM technologies WHERE id = ?').bind('TECH-001').first(),
        env.DB.prepare('SELECT * FROM proposals WHERE id = ?').bind('042').first(),
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
        technology: { research: technology ?? {} }, ledgerEntries: [], persistence: 'cloudflare-d1'
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
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, _env: Env, _ctx: ExecutionContext): Promise<void> {
    // Background settlement/aging work will be connected to the authoritative command bus.
  }
};
