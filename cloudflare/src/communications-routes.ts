import { currentHuman } from './auth-session';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation';
import { withRepository } from './repository';
import {
  listAccessibleChannels,
  listChannelMessages,
  sendChannelMessage,
  listDiplomaticDispatches,
  sendDiplomaticDispatch,
  markDispatchRead,
  getCommunicationsMetrics,
} from './communications-postgres';

export async function communicationsRoutes(
  request: Request,
  env: Env,
  url: URL
): Promise<Response | null> {
  // 1. GET /api/comm/channels
  if (url.pathname === '/api/comm/channels' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    const humanId = human?.id ?? 'H-0044';
    const cityId = (human as Record<string, unknown> | null)?.city_id as string | undefined;

    const channels = await withRepository(env, (repo) =>
      listAccessibleChannels(repo, humanId, cityId)
    );
    if (!channels) return Response.json({ ok: false, error: 'Database unavailable' }, { status: 503 });
    return Response.json({ ok: true, channels, persistence: 'planetscale-postgres' });
  }

  // 2. GET /api/comm/messages?channelId=...&limit=...
  if (url.pathname === '/api/comm/messages' && request.method === 'GET') {
    const channelId = url.searchParams.get('channelId') ?? 'channel-global-relay';
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 50)));

    const messages = await withRepository(env, (repo) =>
      listChannelMessages(repo, channelId, limit)
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
      gameDay?: number;
      gameMinute?: number;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;

    const channelId = parsed.value.channelId ?? 'channel-global-relay';
    const body = (parsed.value.body ?? '').trim();
    if (!body || body.length < 1 || body.length > 2000) {
      return Response.json({ ok: false, error: 'Message body must be between 1 and 2000 characters' }, { status: 400 });
    }

    const message = await withRepository(env, (repo) =>
      sendChannelMessage(
        repo,
        human.id,
        human.displayName ?? human.id,
        ((human as Record<string, unknown>).house_name ?? (human as Record<string, unknown>).dynasty_name) as string | null,
        channelId,
        body,
        parsed.value.gameDay ?? 1,
        parsed.value.gameMinute ?? 0,
        parsed.value.attachments ?? [],
        resolveIdempotencyKey(request, parsed.value.correlationId)
      )
    );
    if (!message) return Response.json({ ok: false, error: 'Failed to send message' }, { status: 500 });
    return Response.json({ ok: true, message, persistence: 'planetscale-postgres' });
  }

  // 4. GET /api/comm/dispatches?folder=inbox|sent|archived
  if (url.pathname === '/api/comm/dispatches' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const folder = (url.searchParams.get('folder') ?? 'inbox') as 'inbox' | 'sent' | 'archived';
    const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 30)));
    const offset = Math.max(0, Number(url.searchParams.get('offset') ?? 0));

    const result = await withRepository(env, (repo) =>
      listDiplomaticDispatches(repo, human.id, folder, limit, offset)
    );
    if (!result) return Response.json({ ok: false, error: 'Database unavailable' }, { status: 503 });
    return Response.json({ ok: true, folder, ...result, persistence: 'planetscale-postgres' });
  }

  // 5. POST /api/comm/dispatches
  if (url.pathname === '/api/comm/dispatches' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const parsed = await parseJsonBody<{
      recipientId?: string;
      subject?: string;
      body?: string;
      dispatchType?: 'diplomatic' | 'contract_offer' | 'patent_license' | 'merger_tender' | 'succession_notice';
      actionPayload?: Record<string, unknown>;
      gameDay?: number;
      gameMinute?: number;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;

    const recipientId = (parsed.value.recipientId ?? '').trim();
    const subject = (parsed.value.subject ?? '').trim();
    const body = (parsed.value.body ?? '').trim();

    if (!recipientId || !subject || !body) {
      return Response.json({ ok: false, error: 'recipientId, subject, and body are required' }, { status: 400 });
    }

    const dispatch = await withRepository(env, (repo) =>
      sendDiplomaticDispatch(
        repo,
        human.id,
        recipientId,
        subject,
        body,
        parsed.value.dispatchType ?? 'diplomatic',
        parsed.value.actionPayload ?? {},
        parsed.value.gameDay ?? 1,
        parsed.value.gameMinute ?? 0,
        resolveIdempotencyKey(request, parsed.value.correlationId)
      )
    );
    if (!dispatch) return Response.json({ ok: false, error: 'Failed to send diplomatic dispatch' }, { status: 500 });
    return Response.json({ ok: true, dispatch, persistence: 'planetscale-postgres' });
  }

  // 6. POST /api/comm/dispatches/read
  if (url.pathname === '/api/comm/dispatches/read' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });

    const parsed = await parseJsonBody<{ dispatchId?: string }>(request);
    if (!parsed.ok) return parsed.response;

    const dispatchId = (parsed.value.dispatchId ?? '').trim();
    if (!dispatchId) return Response.json({ ok: false, error: 'dispatchId is required' }, { status: 400 });

    await withRepository(env, (repo) => markDispatchRead(repo, human.id, dispatchId));
    return Response.json({ ok: true, dispatchId, read: true, persistence: 'planetscale-postgres' });
  }

  // 7. GET /api/comm/metrics
  if (url.pathname === '/api/comm/metrics' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    const humanId = human?.id ?? 'H-0044';

    const metrics = await withRepository(env, (repo) =>
      getCommunicationsMetrics(repo, humanId)
    );
    return Response.json({ ok: true, ...metrics, persistence: 'planetscale-postgres' });
  }

  return null;
}
