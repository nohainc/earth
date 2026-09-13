import type { Env } from './index.ts';
import type { ViewerContext } from './auth-session.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listCommunities,
  getCommunity,
  createCommunity,
  updateCommunity,
  disbandCommunity,
  listCommunityMembershipRequests,
  decideCommunityMembershipRequest,
  setCommunityMemberRole,
  listCommunityMembers,
  changeCommunityMembership,
} from './communities-postgres.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';

export async function handleCommunityRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: ViewerContext,
  sensitiveActionAllowed?: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (!featureEnabled(env, 'communities')) return featureDisabledResponse('communities');
  if (url.pathname === '/api/communities' && request.method === 'GET') {
    const membership = url.searchParams.get('membership') === 'mine' ? 'mine' : undefined;
    const result = await withRepository(env, (repository) => listCommunities(repository, viewer.houseId, membership));
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/communities' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      name?: string;
      description?: string;
      visibility?: 'PUBLIC' | 'PRIVATE';
      joinPolicy?: 'OPEN' | 'REQUEST';
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    if (!name || name.length < 3 || name.length > 80) {
      return Response.json({ ok: false, error: 'Community name must be 3–80 characters' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) {
      return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCommunity(repository, {
          houseId: viewer.houseId,
          humanId: viewer.currentHumanId,
          name,
          description: body.description,
          visibility: body.visibility,
          joinPolicy: body.joinPolicy,
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
  if (communityMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getCommunity(repository, communityMatch[1], viewer.houseId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community could not be loaded' }, { status: 404 }); }
  }
  if (communityMatch && request.method === 'PATCH') {
    const communityId = communityMatch[1];
    const parsed = await parseJsonBody<{ name?: string; description?: string; visibility?: 'PUBLIC' | 'PRIVATE'; joinPolicy?: 'OPEN' | 'REQUEST' }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) =>
        updateCommunity(repository, {
          communityId,
          houseId: viewer.houseId,
          humanId: viewer.currentHumanId,
          name: parsed.value.name,
          description: parsed.value.description,
          visibility: parsed.value.visibility,
          joinPolicy: parsed.value.joinPolicy,
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
      let otp: string | undefined;
      if (sensitiveActionAllowed) { const parsed = await parseJsonBody<{ otp?: string }>(request); if (!parsed.ok) return parsed.response; otp = parsed.value.otp; }
      if (sensitiveActionAllowed && !(await sensitiveActionAllowed(env, viewer.currentHumanId, otp))) return Response.json({ ok: false, error: 'Recent authentication or MFA is required' }, { status: 403 });
      const result = await withRepository(env, (repository) => disbandCommunity(repository, { communityId, houseId: viewer.houseId, humanId: viewer.currentHumanId }));
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
        listCommunityMembershipRequests(repository, communityId, viewer.houseId),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community requests could not be loaded' }, { status: 403 });
    }
  }

  const communityRequestDecisionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/requests\/([^/]+)\/(approve|reject)$/);
  if (communityRequestDecisionMatch && request.method === 'POST') {
    const communityId = communityRequestDecisionMatch[1];
    const requestId = communityRequestDecisionMatch[2];
    const parsed = await parseJsonBody<{ rejectionReason?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const action = communityRequestDecisionMatch[3] as 'approve' | 'reject';
    const rejectionReason = parsed.value.rejectionReason;
    try {
      const result = await withRepository(env, (repository) =>
        decideCommunityMembershipRequest(repository, { communityId, actorHouseId: viewer.houseId, actorHumanId: viewer.currentHumanId, requestId, action, rejectionReason }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Request decision failed' }, { status: 400 });
    }
  }

  const communityMemberRoleMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members\/([^/]+)$/);
  if (communityMemberRoleMatch && request.method === 'PATCH') {
    const communityId = communityMemberRoleMatch[1];
    const targetHouseId = communityMemberRoleMatch[2];
    const parsed = await parseJsonBody<{ role?: 'OWNER' | 'MODERATOR' | 'MEMBER' }>(request);
    if (!parsed.ok) return parsed.response;
    if (!parsed.value.role || !['OWNER', 'MODERATOR', 'MEMBER'].includes(parsed.value.role)) {
      return Response.json({ ok: false, error: 'Invalid community role' }, { status: 400 });
    }
    const role = parsed.value.role;
    try {
      const result = await withRepository(env, (repository) =>
        setCommunityMemberRole(repository, { communityId, actorHouseId: viewer.houseId, actorHumanId: viewer.currentHumanId, targetHouseId, role }),
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
      const result = await withRepository(env, (repository) => listCommunityMembers(repository, communityId, viewer.houseId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Community members could not be loaded' }, { status: 404 });
    }
  }

  const memberActionMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/(join|leave)$/);
  if (memberActionMatch && request.method === 'POST') {
    const communityId = memberActionMatch[1]; const houseId = viewer.houseId;
    const parsed = await parseJsonBody<{ applicationMessage?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const applicationMessage = parsed.value.applicationMessage; const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId) ?? undefined;
    try {
      const result = await withRepository(env, (repository) =>
        changeCommunityMembership(repository, {
          communityId,
          houseId,
          humanId: viewer.currentHumanId,
          action: memberActionMatch[2],
          applicationMessage,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: memberActionMatch[2] === 'join' ? 201 : 200 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Community membership change failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member|active/i.test(message) ? 409 : 400 });
    }
  }

  const memberRemovalMatch = url.pathname.match(/^\/api\/communities\/([^/]+)\/members\/([^/]+)$/);
  if (memberRemovalMatch && request.method === 'DELETE') {
    let otp: string | undefined;
    if (sensitiveActionAllowed) { const parsed = await parseJsonBody<{ otp?: string }>(request); if (!parsed.ok) return parsed.response; otp = parsed.value.otp; }
    if (sensitiveActionAllowed && !(await sensitiveActionAllowed(env, viewer.currentHumanId, otp))) return Response.json({ ok: false, error: 'Recent authentication or MFA is required' }, { status: 403 });
    try {
      const result = await withRepository(env, (repository) => changeCommunityMembership(repository, { communityId: memberRemovalMatch[1], houseId: viewer.houseId, humanId: viewer.currentHumanId, targetHouseId: memberRemovalMatch[2], action: 'remove' }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Member removal failed' }, { status: 400 }); }
  }

  return null;
}
