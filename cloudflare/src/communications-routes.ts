import { currentHuman } from './auth-session';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { withRepository } from './repository';
import {
  listAccessibleChannels,
  listChannelMessages,
  sendChannelMessage,
  openDirectConversation,
  getCommunicationsMetrics,
} from './communications-postgres';
import { getAuthoritativeGameTime } from './game-clock';

export async function communicationsRoutes(
  request: Request,
  env: Env,
  url: URL
): Promise<Response | null> {
  // 1. GET /api/comm/channels
  if (url.pathname === '/api/comm/channels' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const channels = await withRepository(env, (repo) =>
      listAccessibleChannels(repo, human.id)
    );
    if (!channels) return Response.json({ ok: false, error: 'Database unavailable' }, { status: 503 });
    return Response.json({ ok: true, channels, persistence: 'planetscale-postgres' });
  }

  // 2. GET /api/comm/messages?channelId=...&limit=...
  if (url.pathname === '/api/comm/messages' && request.method === 'GET') {
    const channelId = url.searchParams.get('channelId') ?? 'channel-global-relay';
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const messages = await withRepository(env, (repo) =>
      listChannelMessages(repo, human.id, channelId, limit)
    );
    if (!messages) return Response.json({ ok: false, error: 'Database unavailable' }, { status: 503 });
    return Response.json({ ok: true, channelId, messages, persistence: 'planetscale-postgres' });
  }

  // 3. POST /api/comm/messages
  if (url.pathname === '/api/comm/messages' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const parsed = await parseJsonBody<{
      channelId?: string;
      body?: string;
      attachments?: unknown[];
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;

    const channelId = parsed.value.channelId ?? 'channel-global-relay';
    const body = (parsed.value.body ?? '').trim();
    if (!body || body.length < 1 || body.length > 2000) {
      return Response.json({ ok: false, error: 'Message body must be between 1 and 2000 characters' }, { status: 400 });
    }

    const authoritativeClock = getAuthoritativeGameTime();
    const message = await withRepository(env, (repo) =>
      sendChannelMessage(
        repo,
        human.id,
        (human as unknown as { display_name?: string }).display_name ?? (human as unknown as { displayName?: string }).displayName ?? human.id,
        ((human as Record<string, unknown>).house_name ?? (human as Record<string, unknown>).dynasty_name) as string | null,
        channelId,
        body,
        authoritativeClock.gameDay,
        authoritativeClock.gameMinute,
        parsed.value.attachments ?? [],
        resolveIdempotencyKey(request, parsed.value.correlationId)
      )
    );
    if (!message) return Response.json({ ok: false, error: 'Failed to send message' }, { status: 500 });
    return Response.json({ ok: true, message, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/comm/direct' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ targetHumanId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const targetHumanId = parsed.value.targetHumanId?.trim();
    if (!targetHumanId) return Response.json({ ok: false, error: 'Target user is required' }, { status: 400 });
    try {
      const channel = await withRepository(env, (repo) =>
        openDirectConversation(repo, human.id, targetHumanId, resolveIdempotencyKey(request, parsed.value.correlationId)),
      );
      if (!channel) return Response.json({ ok: false, error: 'Conversation could not be opened' }, { status: 500 });
      return Response.json({ ok: true, channel, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Conversation could not be opened' }, { status: 409 });
    }
  }

  // 4. GET /api/comm/metrics
  if (url.pathname === '/api/comm/metrics' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    const humanId = human?.id ?? '';

    const metrics = await withRepository(env, (repo) =>
      getCommunicationsMetrics(repo, humanId)
    );
    return Response.json({ ok: true, ...metrics, persistence: 'planetscale-postgres' });
  }

  return null;
}
