import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listCommunitiesPostgres,
  createCommunityPostgres,
  updateCommunityPostgres,
  disbandCommunityPostgres,
  listCommunityMembershipRequestsPostgres,
  decideCommunityMembershipRequestPostgres,
  setCommunityMemberRolePostgres,
  listCommunityMembersPostgres,
  changeCommunityMembershipPostgres,
  listCommunityContributionsPostgres,
  contributeToCommunityPostgres,
} from './communities-postgres.ts';

export async function handleCommunityRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/communities' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCommunitiesPostgres(repository));
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/communities' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      name?: string;
      description?: string;
      admissionPolicy?: 'open' | 'approval';
      applicationQuestion?: string;
      founderId?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const founderId = viewer.id;
    if (!name || name.length < 3 || name.length > 80) {
      return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCommunityPostgres(repository, {
          founderId,
          name,
          description: body.description,
          admissionPolicy: body.admissionPolicy,
          applicationQuestion: body.applicationQuestion,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Community formation failed';
      return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /founder/i.test(message) ? 404 : 400 });
    }
  }

  const communityMatch = url.pathname.match(/^\/api\/communities\/([^/]+)$/);
  if (communityMatch && request.method === 'PATCH') {
    const communityId = communityMatch[1];
    const parsed = await parseJsonBody<{ description?: string; admissionPolicy?: 'open' | 'approval'; applicationQuestion?: string }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) =>
        updateCommunityPostgres(repository, {
          communityId,
          humanId: viewer.id,
          description: parsed.value.description,
          admissionPolicy: parsed.value.admissionPolicy,
          applicationQuestion: parsed.value.applicationQuestion,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community update failed' }, { status: 400 });
    }
  }

  if (communityMatch && request.method === 'DELETE') {
    const communityId = communityMatch[1];
    try {
      const result = await withRepository(env, (repository) =>
        disbandCommunityPostgres(repository, { communityId, humanId: viewer.id }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community disband failed' }, { status: 400 });
    }
  }

  const communityRequestsMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/requests$/);
  if (communityRequestsMatch && request.method === 'GET') {
    const communityId = communityRequestsMatch[1];
    try {
      const result = await withRepository(env, (repository) =>
        listCommunityMembershipRequestsPostgres(repository, communityId, viewer.id),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community requests could not be loaded' }, { status: 403 });
    }
  }

  const communityRequestDecisionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/requests\/([^/]+)$/);
  if (communityRequestDecisionMatch && request.method === 'POST') {
    const communityId = communityRequestDecisionMatch[1];
    const requestId = communityRequestDecisionMatch[2];
    const parsed = await parseJsonBody<{ action?: 'approve' | 'reject'; rejectionReason?: string }>(request);
    if (!parsed.ok) return parsed.response;
    if (parsed.value.action !== 'approve' && parsed.value.action !== 'reject') {
      return Response.json({ ok: false, error: 'Request action must be approve or reject' }, { status: 400 });
    }
    const action = parsed.value.action;
    const rejectionReason = parsed.value.rejectionReason;
    try {
      const result = await withRepository(env, (repository) =>
        decideCommunityMembershipRequestPostgres(repository, { communityId, deciderId: viewer.id, requestId, action, rejectionReason }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Request decision failed' }, { status: 400 });
    }
  }

  const communityMemberRoleMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members\/([^/]+)\/role$/);
  if (communityMemberRoleMatch && request.method === 'POST') {
    const communityId = communityMemberRoleMatch[1];
    const targetHumanId = communityMemberRoleMatch[2];
    const parsed = await parseJsonBody<{ role?: 'admin' | 'member' }>(request);
    if (!parsed.ok) return parsed.response;
    if (parsed.value.role !== 'admin' && parsed.value.role !== 'member') {
      return Response.json({ ok: false, error: 'Member role must be admin or member' }, { status: 400 });
    }
    const role = parsed.value.role;
    try {
      const result = await withRepository(env, (repository) =>
        setCommunityMemberRolePostgres(repository, { communityId, actorId: viewer.id, targetHumanId, role }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Role change failed' }, { status: 400 });
    }
  }

  const communityMembersMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members$/);
  if (communityMembersMatch && request.method === 'GET') {
    const communityId = communityMembersMatch[1];
    try {
      const result = await withRepository(env, (repository) => listCommunityMembersPostgres(repository, communityId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community members could not be loaded' }, { status: 404 });
    }
  }

  if (communityMembersMatch && (request.method === 'POST' || request.method === 'DELETE')) {
    const communityId = communityMembersMatch[1];
    const humanId = viewer.id;
    let applicationMessage: string | undefined;
    if (request.method === 'POST') {
      const parsed = await parseJsonBody<{ applicationMessage?: string }>(request);
      if (parsed.ok) {
        applicationMessage = parsed.value.applicationMessage;
      }
    }
    try {
      const result = await withRepository(env, (repository) =>
        changeCommunityMembershipPostgres(repository, {
          communityId,
          humanId,
          action: request.method === 'POST' ? 'join' : 'leave',
          applicationMessage,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: request.method === 'POST' ? 201 : 200 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Community membership change failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member|active/i.test(message) ? 409 : 400 });
    }
  }

  const communityContributionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/contributions$/);
  if (communityContributionMatch && request.method === 'GET') {
    const communityId = communityContributionMatch[1];
    try {
      const result = await withRepository(env, (repository) => listCommunityContributionsPostgres(repository, communityId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community contributions could not be loaded' }, { status: 404 });
    }
  }

  if (communityContributionMatch && request.method === 'POST') {
    const communityId = communityContributionMatch[1];
    const parsed = await parseJsonBody<{ humanId?: string; amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const humanId = viewer.id;
    const amount = Math.round(Number(body.amount) * 100) / 100;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      return Response.json({ ok: false, error: 'Contribution amount must be positive' }, { status: 400 });
    }
    if (amount > 100000) {
      return Response.json({ ok: false, error: 'Contribution exceeds the per-command limit' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        contributeToCommunityPostgres(repository, { communityId, humanId, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Community contribution failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|balance/i.test(message) ? 409 : /not found/i.test(message) ? 404 : 400 });
    }
  }

  return null;
}
