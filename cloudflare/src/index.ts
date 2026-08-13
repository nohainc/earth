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
    if (url.pathname === '/api/world') {
      const world = await env.DB.prepare('SELECT * FROM world_state WHERE id = ?').bind('WORLD').first();
      return Response.json({ world, persistence: 'cloudflare-d1' });
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
