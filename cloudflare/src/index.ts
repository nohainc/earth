export interface Env {
  ENVIRONMENT: string;
  HYPERDRIVE: Hyperdrive;
  MARKET_COORDINATOR: DurableObjectNamespace;
}

export class MarketCoordinator {
  constructor(private readonly state: DurableObjectState, private readonly env: Env) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method === 'POST') {
      const payload = await request.json<unknown>();
      await this.state.storage.put('lastCommand', { payload, at: new Date().toISOString() });
      return Response.json({ ok: true, coordinator: 'market', accepted: true });
    }
    return Response.json({ ok: true, coordinator: 'market', state: await this.state.storage.get('lastCommand') });
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/edge/market') {
      const id = env.MARKET_COORDINATOR.idFromName('central-market');
      return env.MARKET_COORDINATOR.get(id).fetch(request);
    }
    return Response.json({ service: 'earth-world', environment: env.ENVIRONMENT, status: 'edge-ready' });
  },
  async scheduled(_event: ScheduledEvent, _env: Env, _ctx: ExecutionContext): Promise<void> {
    // Background settlement/aging work will be connected to the authoritative command bus.
  }
};
