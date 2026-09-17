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
} from './governance-postgres.ts';
import { createProposalV3, castVoteV3 } from './governance-v3-postgres.ts';
import { castGovernanceVoteV4, createGovernanceProposalV4, getOrganizationVotingSettings, resolveGovernanceProposalV4, setOrganizationVotingSettings } from './governance-v4-postgres.ts';
import { castV5GovernanceVote, createV5GovernanceProposal, listV5GovernanceProposals, resolveV5GovernanceProposal } from './v5-governance-postgres.ts';
import { getConstitutionReadModel, getResolvedConstitutionForDay } from './constitutional-kernel-postgres.ts';
import { getConstitutionalRuleDefinition } from './v5-constitution.ts';
import { previewConstitutionAmendment } from './v5-governance.ts';

export async function handleGovernanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/governance/v5/constitution/preview' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ corporationId?: string | null; changes?: Array<{ ruleCode?: string; value?: unknown; clearOverride?: boolean }> }>(request);
    if (!parsed.ok) return parsed.response;
    const corporationId = parsed.value.corporationId?.trim() || undefined;
    if (!parsed.value.changes?.length) return Response.json({ ok: false, error: 'At least one Constitution change is required' }, { status: 400 });
    try {
      const result = await withRepository(env, async (repository) => {
        if (corporationId) {
          const allowed = (await repository.query(`SELECT 1 FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.corporation_id = $2 AND h.status = 'ACTIVE' AND ha.status = 'ACTIVE'`, [viewer.id, corporationId])).rows[0];
          if (!allowed) throw new Error('Corporation membership is required to preview its Constitution');
        }
        const world = (await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0];
        const gameDay = Number(world?.game_day ?? 1);
        const current = await getResolvedConstitutionForDay(repository, { corporationId, gameDay });
        const earth = corporationId ? await getResolvedConstitutionForDay(repository, { gameDay }) : undefined;
        for (const change of parsed.value.changes!) {
          const definition = getConstitutionalRuleDefinition(String(change.ruleCode ?? ''));
          if (!corporationId && definition.authorityModel === 'CORPORATION_LOCAL') throw new Error('Corporation-local rule cannot be previewed at Earth scope');
          if (corporationId && definition.authorityModel === 'EARTH_LOCKED') throw new Error('Earth-locked rule cannot be previewed at Corporation scope');
          if (corporationId && change.clearOverride && definition.authorityModel !== 'EARTH_DEFAULT_CORPORATION_OVERRIDE') throw new Error('Only Earth-default Corporation overrides can be cleared');
        }
        const preview = previewConstitutionAmendment({ currentRules: current.rules, fallbackRules: earth?.rules, changes: parsed.value.changes!.map((change) => ({ ruleCode: String(change.ruleCode ?? ''), value: change.value, clearOverride: change.clearOverride })) });
        return { ...preview, gameDay, corporationId: corporationId ?? null, versionIds: current.versionIds, generatedFrom: 'postgres-constitutional-kernel-v5-preview' };
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return new Response(JSON.stringify({ ok: true, ...result }, (_, value) => typeof value === 'bigint' ? value.toString() : value), { headers: { 'content-type': 'application/json; charset=utf-8' } });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Constitution preview failed' }, { status: 400 }); }
  }
  if (url.pathname === '/api/governance/v5/constitution' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const corporationId = url.searchParams.get('corporationId')?.trim() || undefined;
      if (corporationId) {
        const allowed = (await repository.query(`SELECT 1 FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.corporation_id = $2 AND h.status = 'ACTIVE' AND ha.status = 'ACTIVE'`, [viewer.id, corporationId])).rows[0];
        if (!allowed) throw new Error('Corporation membership is required to view its Constitution');
      }
      const world = (await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0];
      return getConstitutionReadModel(repository, { gameDay: Number(world?.game_day ?? 1), corporationId });
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/governance/v5/proposals' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listV5GovernanceProposals(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/governance/v5/proposals' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ subjectType?: 'EARTH' | 'CORPORATION'; subjectId?: string | null; actionType?: 'CONSTITUTION_AMENDMENT'; payload?: Record<string, unknown>; title?: string; body?: string; correlationId?: string }>(request);
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
    const result = await withRepository(env, async (repository) => {
      const world = (await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0];
      return getConstitutionReadModel(repository, { gameDay: Number(world?.game_day ?? 1) });
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/governance/v4/proposals' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ subjectType?: 'EARTH' | 'ORGANIZATION'; subjectId?: string | null; title?: string; body?: string; actionType?: string; actionSnapshot?: Record<string, unknown>; ruleSnapshot?: Record<string, unknown>; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    if (['TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX'].includes(String(parsed.value.actionType ?? '').toUpperCase())) {
      return Response.json({ ok: false, error: 'Legacy tax governance is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
    }
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
    const targetTaxAction = String(body.target?.value && typeof body.target.value === 'object' ? (body.target.value as Record<string, unknown>).actionType ?? '' : '').toUpperCase();
    if (targetCategory) {
      return Response.json({ ok: false, error: 'Executable governance targets are retired; submit a typed V5 Constitution proposal or use the dedicated operational workflow.' }, { status: 410 });
    }
    if (targetCategory === 'tax' || ['TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX'].includes(targetTaxAction)) {
      return Response.json({ ok: false, error: 'Legacy tax governance is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
    }
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
    return Response.json({ ok: false, error: 'Direct rule mutation is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
  }

  return null;
}
