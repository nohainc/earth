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
  updateRulePostgres,
} from './governance-postgres.ts';
import { createProposalV3, castVoteV3 } from './governance-v3-postgres.ts';
import { castGovernanceVoteV4, createGovernanceProposalV4, getOrganizationVotingSettings, resolveGovernanceProposalV4, setOrganizationVotingSettings } from './governance-v4-postgres.ts';
import { castV5GovernanceVote, createV5GovernanceProposal, listV5GovernanceProposals, resolveV5GovernanceProposal } from './v5-governance-postgres.ts';

export async function handleGovernanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/governance/v5/proposals' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listV5GovernanceProposals(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/governance/v5/proposals' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ subjectType?: 'EARTH' | 'CORPORATION'; subjectId?: string | null; actionType?: 'CONSTITUTION_AMENDMENT' | 'EARTH_CAPACITY_POLICY' | 'CORPORATION_HOUSE_RATE' | 'PROGRESSIVE_SCHEDULE' | 'CORPORATION_ADMISSION_POLICY'; payload?: Record<string, unknown>; title?: string; body?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.subjectType || !parsed.value.actionType || !parsed.value.payload || !parsed.value.title?.trim()) return Response.json({ ok: false, error: 'Subject, action, payload, title, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createV5GovernanceProposal(repository, { humanId: viewer.id, subjectType: parsed.value.subjectType!, subjectId: parsed.value.subjectId ?? null, actionType: parsed.value.actionType!, payload: parsed.value.payload!, title: parsed.value.title!, body: parsed.value.body, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 proposal creation failed' }, { status: 409 }); }
  }
  const v5Vote = url.pathname.match(/^\/api\/governance\/v5\/proposals\/([^/]+)\/vote$/);
  if (v5Vote && request.method === 'POST') {
    const parsed = await parseJsonBody<{ choice?: 'SUPPORT' | 'OPPOSE' | 'ABSTAIN'; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.choice || !['SUPPORT', 'OPPOSE', 'ABSTAIN'].includes(parsed.value.choice)) return Response.json({ ok: false, error: 'Valid choice and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => castV5GovernanceVote(repository, { humanId: viewer.id, proposalId: v5Vote[1], choice: parsed.value.choice!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 ballot failed' }, { status: 409 }); }
  }
  const v5Resolve = url.pathname.match(/^\/api\/governance\/v5\/proposals\/([^/]+)\/resolve$/);
  if (v5Resolve && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) => resolveV5GovernanceProposal(repository, v5Resolve[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V5 proposal resolution failed' }, { status: 409 }); }
  }

  if (url.pathname === '/api/governance/rules' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query(
      "SELECT id, institution_id, name, category, value_json, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days, version, status, effective_from_game_day, effective_to_game_day FROM governance_rules WHERE status = 'active' ORDER BY institution_id, category, version DESC",
    ));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ rules: result.rows, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/governance/v4/proposals' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ subjectType?: 'EARTH' | 'ORGANIZATION'; subjectId?: string | null; title?: string; body?: string; actionType?: string; actionSnapshot?: Record<string, unknown>; ruleSnapshot?: Record<string, unknown>; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.title || !parsed.value.actionType || !parsed.value.actionSnapshot) return Response.json({ ok: false, error: 'Subject, title, action, snapshot, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createGovernanceProposalV4(repository, { humanId: viewer.id, subjectType: parsed.value.subjectType ?? 'EARTH', subjectId: parsed.value.subjectId ?? null, title: parsed.value.title!, body: parsed.value.body, actionType: parsed.value.actionType!, actionSnapshot: parsed.value.actionSnapshot!, ruleSnapshot: parsed.value.ruleSnapshot, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V4 proposal creation failed' }, { status: 409 }); }
  }
  const methodMatch = url.pathname.match(/^\/api\/governance\/v4\/organizations\/([^/]+)\/method$/);
  if (methodMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getOrganizationVotingSettings(repository, methodMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (methodMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Direct voting-setting mutation is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
    /* istanbul ignore next -- retained below for migration/admin callers, not the player route. */
    const parsed = await parseJsonBody<{ votingMethod?: 'ONE_HOUSE_ONE_VOTE' | 'DELEGATED' | 'SHARE_WEIGHTED' | 'QUADRATIC_VOICE'; voiceCycleDays?: number; voicePerCycle?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.votingMethod) return Response.json({ ok: false, error: 'Voting method and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => setOrganizationVotingSettings(repository, { organizationId: methodMatch[1], humanId: viewer.id, votingMethod: parsed.value.votingMethod!, voiceCycleDays: parsed.value.voiceCycleDays, voicePerCycle: parsed.value.voicePerCycle, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Voting method update failed' }, { status: 409 }); }
  }
  const v4VoteMatch = url.pathname.match(/^\/api\/governance\/v4\/proposals\/([^/]+)\/vote$/);
  if (v4VoteMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ choice?: 'SUPPORT' | 'OPPOSE' | 'ABSTAIN'; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.choice || !['SUPPORT', 'OPPOSE', 'ABSTAIN'].includes(parsed.value.choice)) return Response.json({ ok: false, error: 'Valid choice and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => castGovernanceVoteV4(repository, { proposalId: v4VoteMatch[1], humanId: viewer.id, choice: parsed.value.choice!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V4 ballot failed' }, { status: 409 }); }
  }
  const v4ResolveMatch = url.pathname.match(/^\/api\/governance\/v4\/proposals\/([^/]+)\/resolve$/);
  if (v4ResolveMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) => resolveGovernanceProposalV4(repository, v4ResolveMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'V4 proposal resolution failed' }, { status: 409 }); }
  }

  if (url.pathname === '/api/governance/proposals' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query(
      'SELECT id, institution_id, created_by_human_id, action_type, status, created_game_day FROM proposals ORDER BY created_game_day DESC, id DESC LIMIT 100',
    ));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ proposals: result.rows, persistence: 'planetscale-postgres' });
  }

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
      expectedGovernanceRuleVersionId?: string;
      target?: { category?: string; value?: unknown };
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const institutionId = body.institutionId?.trim();
    const title = body.title?.trim();
    const proposalBody = body.body?.trim();
    if (!institutionId || !title || title.length < 3 || title.length > 120 || !proposalBody || proposalBody.length < 10 || proposalBody.length > 4000) {
      return Response.json({ ok: false, error: 'Title must be 3–120 characters and description 10–4000 characters' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    const targetCategory = body.target?.category?.trim() || null;
    if (targetCategory && !['market', 'finance', 'services', 'technology', 'territory'].includes(targetCategory)) {
      return Response.json({ ok: false, error: 'Unsupported target rule category' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createProposalV3(repository, {
          humanId: viewer.id,
          institutionId,
          title,
          body: proposalBody,
          expectedGovernanceRuleVersionId: body.expectedGovernanceRuleVersionId,
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
        castVoteV3(repository, { proposalId: voteMatch[1], humanId: viewer.id, choice: body.vote! }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Ballot failed';
      return Response.json({ ok: false, error: message }, { status: /already/i.test(message) ? 409 : /not found/i.test(message) ? 404 : 403 });
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
