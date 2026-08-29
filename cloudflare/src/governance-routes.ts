import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listRolesPostgres,
  changeRolePostgres,
  changeDelegationPostgres,
} from './roles-postgres.ts';
import {
  createProposalPostgres,
  castVotePostgres,
  executeProposalPostgres,
  challengeProposalPostgres,
  updateRulePostgres,
} from './governance-postgres.ts';

export async function handleGovernanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/governance/roles' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listRolesPostgres(repository));
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const roleClaimMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(claim|resign)$/);
  if (roleClaimMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) =>
        changeRolePostgres(repository, {
          humanId: viewer.id,
          roleId: roleClaimMatch[1],
          action: roleClaimMatch[2] as 'claim' | 'resign',
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Role operation failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|assignment|eligible|maturity/i.test(message) ? 409 : 403 });
    }
  }

  const delegationMatch = url.pathname.match(/^\/api\/governance\/roles\/([^/]+)\/(delegate|recall)$/);
  if (delegationMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ delegateHumanId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    try {
      const result = await withRepository(env, (repository) =>
        changeDelegationPostgres(repository, {
          humanId: viewer.id,
          roleId: delegationMatch[1],
          action: delegationMatch[2] as 'delegate' | 'recall',
          delegateHumanId: body.delegateHumanId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Delegation operation failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /occupied|currently|eligible|holder/i.test(message) ? 409 : 403 });
    }
  }

  if (url.pathname === '/api/governance/proposals' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      institutionId?: string;
      title?: string;
      body?: string;
      durationHours?: number;
      ruleVersionId?: string;
      target?: { category?: string; value?: unknown };
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const institutionId = body.institutionId?.trim();
    const title = body.title?.trim();
    const proposalBody = body.body?.trim();
    const durationHours = Number(body.durationHours ?? 72);
    if (!institutionId || !title || title.length < 3 || title.length > 120 || !proposalBody || proposalBody.length < 10 || proposalBody.length > 4000) {
      return Response.json({ ok: false, error: 'Title must be 3–120 characters and description 10–4000 characters' }, { status: 400 });
    }
    if (!Number.isInteger(durationHours) || durationHours < 24 || durationHours > 168) {
      return Response.json({ ok: false, error: 'Decision window must be between 24 and 168 hours' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    const targetCategory = body.target?.category?.trim() || null;
    if (targetCategory && !['market', 'finance', 'services', 'technology', 'megaproject_procurement'].includes(targetCategory)) {
      return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createProposalPostgres(repository, {
          humanId: viewer.id,
          institutionId,
          title,
          body: proposalBody,
          durationHours,
          ruleVersionId: body.ruleVersionId,
          targetCategory,
          targetValue: body.target?.value ?? null,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Proposal creation failed' }, { status: 409 });
    }
  }

  const voteMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/vote$/);
  if (voteMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ vote?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!['support', 'oppose', 'abstain'].includes(body.vote ?? '')) {
      return Response.json({ ok: false, error: 'Invalid ballot choice' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        castVotePostgres(repository, { proposalId: voteMatch[1], humanId: viewer.id, choice: body.vote! }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Ballot failed';
      return Response.json({ ok: false, error: message }, { status: /already/i.test(message) ? 409 : /not found/i.test(message) ? 404 : 403 });
    }
  }

  const executeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/execute$/);
  if (executeProposalMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) =>
        executeProposalPostgres(repository, { proposalId: executeProposalMatch[1], humanId: viewer.id }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Proposal execution failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  const challengeProposalMatch = url.pathname.match(/^\/api\/governance\/proposals\/([^/]+)\/challenge$/);
  if (challengeProposalMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ reason?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const reason = body.reason?.trim() ?? 'Constitutional appeal filed during delay window';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        challengeProposalPostgres(repository, {
          proposalId: challengeProposalMatch[1],
          humanId: viewer.id,
          reason,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Proposal challenge failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/governance/rules' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ ruleId?: string; version?: string; active?: boolean; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const ruleId = body.ruleId?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!ruleId || !correlationId) return Response.json({ ok: false, error: 'Rule ID and correlation ID are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        updateRulePostgres(repository, { humanId: viewer.id, ruleId, version: body.version, active: body.active, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Rule update failed' }, { status: 409 });
    }
  }

  return null;
}
