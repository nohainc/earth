import type { Env } from './index.ts';
import { currentViewer } from './auth-session.ts';
export { mapToRealtimeInvalidation } from './realtime-protocol.ts';

function realtimeOriginAllowed(request: Request, env: Env): boolean {
  const origin = request.headers.get('Origin');
  if (!origin) return true;
  const configured = String((env as unknown as Record<string, unknown>).CORS_ORIGIN ?? 'https://earthuc.com')
    .split(',').map((value) => value.trim()).filter(Boolean);
  const host = new URL(request.url).hostname;
  if (host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]') return true;
  return configured.includes(origin);
}

export async function handleRealtimeRoute(request: Request, env: Env, url: URL): Promise<Response | null> {
  if (url.pathname !== '/api/realtime' || request.method !== 'GET') return null;
  const viewer = await currentViewer(request, env);
  if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
  if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket' && !realtimeOriginAllowed(request, env)) {
    return Response.json({ ok: false, error: 'Origin not allowed' }, { status: 403 });
  }
  if (!env.MARKET_COORDINATOR) return Response.json({ ok: false, error: 'Realtime service unavailable' }, { status: 503 });
  const coordinator = env.MARKET_COORDINATOR.getByName('events-global');
  return coordinator.fetch(new Request('https://realtime.internal/api/realtime', request));
}
