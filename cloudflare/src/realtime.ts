import type { Env } from './index.ts';
import { currentViewer } from './auth-session.ts';
export { mapToRealtimeInvalidation } from './realtime-protocol.ts';

export async function handleRealtimeRoute(request: Request, env: Env, url: URL): Promise<Response | null> {
  if (url.pathname !== '/api/realtime' || request.method !== 'GET') return null;
  const viewer = await currentViewer(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  if (!env.MARKET_COORDINATOR) return Response.json({ ok: false, error: 'Realtime service unavailable' }, { status: 503 });
  const coordinator = env.MARKET_COORDINATOR.getByName('events-global');
  return coordinator.fetch(new Request('https://realtime.internal/api/realtime', request));
}
