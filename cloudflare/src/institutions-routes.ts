import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listCorporations,
  listCorporationTerritories,
  createCorporation,
  corporationQualification,
  setCorporationTaxCharter,
  changeCorporationMembership,
  setCorporationAdmissionPolicy,
  contributeToCorporation,
} from './institutions-postgres.ts';
import { getInstitutionBudget, listInstitutionBudgetLines, listInstitutionCommitments, createInstitutionCommitment, payInstitutionCommitment, cancelInstitutionCommitment } from './institution-budget-api.ts';
import { applyV5CorporationMembership, decideV5MembershipApplication, issueV5CorporationInvite, leaveV5Corporation, listV5MembershipApplications, quoteV5CorporationMembership } from './v5-membership-postgres.ts';
import { foundV5Corporation, quoteV5CorporationFounding } from './v5-founding-postgres.ts';

export async function handleInstitutionRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/v5/corporations/founding/quote' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => quoteV5CorporationFounding(repository, viewer.id, parsed.value.name ?? ''));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation founding quote unavailable' }, { status: 409 }); }
  }
  if (url.pathname === '/api/v5/corporations' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; admissionPolicy?: 'OPEN' | 'APPROVAL' | 'INVITE_ONLY'; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.name || !parsed.value.admissionPolicy || !['OPEN', 'APPROVAL', 'INVITE_ONLY'].includes(parsed.value.admissionPolicy)) return Response.json({ ok: false, error: 'Name, admission policy, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => foundV5Corporation(repository, { humanId: viewer.id, name: parsed.value.name!, admissionPolicy: parsed.value.admissionPolicy!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation founding failed' }, { status: 409 }); }
  }

  const v5Membership = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/membership$/);
  if (v5Membership && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => quoteV5CorporationMembership(repository, viewer.id, v5Membership[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Membership quote unavailable' }, { status: 409 }); }
  }
  if (v5Membership && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string; inviteToken?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => applyV5CorporationMembership(repository, { humanId: viewer.id, corporationId: v5Membership[1], correlationId, inviteToken: parsed.value.inviteToken }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.status === 'PENDING' ? 202 : 200 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation membership failed' }, { status: 409 }); }
  }
  const v5Leave = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/membership\/leave$/);
  if (v5Leave && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => leaveV5Corporation(repository, { humanId: viewer.id, corporationId: v5Leave[1], correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation departure failed' }, { status: 409 }); }
  }
  const v5ApplicationDecision = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/membership\/applications\/([^/]+)$/);
  const v5ApplicationQueue = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/membership\/applications$/);
  if (v5ApplicationQueue && request.method === 'GET') {
    const rawStatus = url.searchParams.get('status')?.toUpperCase() as 'PENDING' | 'APPROVED' | 'REJECTED' | 'WITHDRAWN' | undefined;
    if (rawStatus && !['PENDING', 'APPROVED', 'REJECTED', 'WITHDRAWN'].includes(rawStatus)) return Response.json({ ok: false, error: 'Invalid application status' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => listV5MembershipApplications(repository, { humanId: viewer.id, corporationId: v5ApplicationQueue[1], status: rawStatus }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Membership applications unavailable' }, { status: 403 }); }
  }
  if (v5ApplicationDecision && request.method === 'PATCH') {
    const parsed = await parseJsonBody<{ decision?: 'APPROVED' | 'REJECTED'; reason?: string }>(request);
    if (!parsed.ok) return parsed.response;
    if (!parsed.value.decision) return Response.json({ ok: false, error: 'Decision is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => decideV5MembershipApplication(repository, { humanId: viewer.id, corporationId: v5ApplicationDecision[1], applicationId: v5ApplicationDecision[2], decision: parsed.value.decision!, reason: parsed.value.reason }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Membership application decision failed' }, { status: 409 }); }
  }
  const v5Invites = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/invites$/);
  if (v5Invites && request.method === 'POST') {
    const parsed = await parseJsonBody<{ targetHouseId?: string; expiresGameDay?: number; maxUses?: number }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => issueV5CorporationInvite(repository, { humanId: viewer.id, corporationId: v5Invites[1], targetHouseId: parsed.value.targetHouseId, expiresGameDay: Number(parsed.value.expiresGameDay), maxUses: Number(parsed.value.maxUses ?? 1) }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation invite creation failed' }, { status: 409 }); }
  }

  const v5DelegateLeadership = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/leadership\/delegate$/);
  if (v5DelegateLeadership && request.method === 'POST') {
    const parsed = await parseJsonBody<{ targetHumanId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.targetHumanId) return Response.json({ ok: false, error: 'Target human ID and idempotency key are required' }, { status: 400 });
    try {
      const { delegateV5CorporationLeadership } = await import('./v5-membership-postgres.ts');
      const result = await withRepository(env, (repository) => delegateV5CorporationLeadership(repository, { humanId: viewer.id, corporationId: v5DelegateLeadership[1], targetHumanId: parsed.value.targetHumanId!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Leadership delegation failed' }, { status: 409 }); }
  }

  const v5ScheduleDissolution = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/dissolution\/schedule$/);
  if (v5ScheduleDissolution && request.method === 'POST') {
    const parsed = await parseJsonBody<{ reason?: string; transitionDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const { scheduleV5CorporationDissolution } = await import('./v5-membership-postgres.ts');
      const result = await withRepository(env, (repository) => scheduleV5CorporationDissolution(repository, { humanId: viewer.id, corporationId: v5ScheduleDissolution[1], reason: parsed.value.reason, transitionDays: parsed.value.transitionDays, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation dissolution scheduling failed' }, { status: 409 }); }
  }

  const institutionBudgetMatch = url.pathname.match(/^\/api\/institutions\/([^/]+)\/budget(?:\/(lines|commitments|fiscal-summary|financial-projection))?$/);
  if (institutionBudgetMatch && request.method === 'GET') {
    const institutionId = institutionBudgetMatch[1];
    const kind = institutionBudgetMatch[2];
    const fiscalPeriodId = url.searchParams.get('fiscalPeriodId') ?? undefined;
    const gameDay = Number(url.searchParams.get('gameDay')) || undefined;
    const result = await withRepository(env, async (repository) => {
      if (kind === 'lines') return { lines: await listInstitutionBudgetLines(repository, institutionId, fiscalPeriodId) };
      if (kind === 'commitments') return { commitments: await listInstitutionCommitments(repository, institutionId, fiscalPeriodId) };
      const budget = await getInstitutionBudget(repository, institutionId, gameDay);
      if (kind === 'fiscal-summary') return { fiscalSummary: budget ? { periodRevenueUnits: budget.period_revenue_units, periodSpendingUnits: budget.period_spending_units, surplusDeficitUnits: budget.surplus_deficit_units, budgetAuthorizedUnits: budget.budget_authorized_units, budgetCommittedUnits: budget.budget_committed_units, budgetSpentUnits: budget.budget_spent_units } : null };
      if (kind === 'financial-projection') return { financialProjection: budget };
      return { budget };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const commitmentMatch = url.pathname.match(/^\/api\/institutions\/([^/]+)\/budget\/commitments(?:\/([^/]+))?$/);
  if (commitmentMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ budgetLineId?: string; commitmentType?: string; sourceType?: string; sourceId?: string; amountUnits?: string | number; dueGameDay?: number }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    try {
      const amountUnits = BigInt(body.amountUnits ?? 0);
      const result = await withRepository(env, (repository) => repository.transaction(async (tx) => {
        const clock = await readAuthoritativeGameTime(tx);
        const gameDay = clock.gameDay;
        if (!body.budgetLineId || !body.commitmentType || !body.sourceType || !body.sourceId) throw new Error('Commitment fields are required');
        return createInstitutionCommitment(tx, { humanId: viewer.id, institutionId: commitmentMatch[1], budgetLineId: body.budgetLineId, commitmentType: body.commitmentType, sourceType: body.sourceType, sourceId: body.sourceId, amountUnits, gameDay, dueGameDay: Number(body.dueGameDay ?? gameDay) });
      }));
      return Response.json({ commitmentId: result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Commitment creation failed' }, { status: 400 });
    }
  }

  if (commitmentMatch && commitmentMatch[2] && request.method === 'PATCH') {
    const parsed = await parseJsonBody<{ action?: 'pay' | 'cancel'; amountUnits?: string | number }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => repository.transaction(async (tx) => {
        const clock = await readAuthoritativeGameTime(tx);
        const gameDay = clock.gameDay;
        if (parsed.value.action === 'cancel') return cancelInstitutionCommitment(tx, { humanId: viewer.id, institutionId: commitmentMatch[1], commitmentId: commitmentMatch[2]!, gameDay });
        return payInstitutionCommitment(tx, { humanId: viewer.id, institutionId: commitmentMatch[1], commitmentId: commitmentMatch[2]!, amountUnits: BigInt(parsed.value.amountUnits ?? 0), gameDay });
      }));
      return Response.json({ result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Commitment update failed' }, { status: 400 });
    }
  }
  if (url.pathname === '/api/corporations' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCorporations(repository, url.searchParams.get('search') ?? ''));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/corporations' && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Legacy Corporation founding is retired; use /api/v5/corporations.' }, { status: 410 });
    /* istanbul ignore next -- retained below for migration/admin callers, not the player route. */
    const parsed = await parseJsonBody<{ name?: string; territoryName?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const territoryName = body.territoryName?.trim();
    if (!name || name.length < 3 || name.length > 80) {
      return Response.json({ ok: false, error: 'Corporation name is required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCorporation(repository, { founderId: viewer.id, territoryName, name }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation formation failed';
      return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
    }
  }

  const corporationTerritoriesMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/territories$/);
  if (corporationTerritoriesMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCorporationTerritories(repository, corporationTerritoriesMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const corporationQualificationMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/qualification$/);
  if (corporationQualificationMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => corporationQualification(repository, corporationQualificationMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation qualification unavailable' }, { status: 404 });
    }
  }

  const corporationTaxCharterMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/tax-charter$/);
  if (corporationTaxCharterMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Direct Corporation tax mutation is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
    /* istanbul ignore next -- retained below for migration/admin callers, not the player route. */
    const parsed = await parseJsonBody<{ incomeTaxBps?: number; salesTaxBps?: number; corporateTaxBps?: number; propertyTaxBps?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setCorporationTaxCharter(repository, {
          humanId: viewer.id,
          corporationId: corporationTaxCharterMatch[1],
          incomeTaxBps: Number(body.incomeTaxBps ?? 0),
          salesTaxBps: Number(body.salesTaxBps ?? 0),
          corporateTaxBps: Number(body.corporateTaxBps ?? 0),
          propertyTaxBps: Number(body.propertyTaxBps ?? 0),
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation tax charter update failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
    }
  }

  const corporationMembershipMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/membership$/);
  if (corporationMembershipMatch && (request.method === 'POST' || request.method === 'DELETE')) {
    return Response.json({ ok: false, error: 'Legacy Corporation membership is retired; use the V5 membership command.' }, { status: 410 });
    /* istanbul ignore next -- retained below for migration/admin callers, not the player route. */
    try {
      const result = await withRepository(env, (repository) =>
        changeCorporationMembership(repository, {
          humanId: viewer.id,
          corporationId: corporationMembershipMatch[1],
          action: request.method === 'POST' ? 'join' : 'leave',
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation membership change failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|member/i.test(message) ? 409 : 400 });
    }
  }

  const corporationAdmissionMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/admission-policy$/);
  if (corporationAdmissionMatch && request.method === 'POST') {
    return Response.json({ ok: false, error: 'Direct admission-policy mutation is retired; submit a V5 Constitution amendment proposal.' }, { status: 410 });
    /* istanbul ignore next -- retained below for migration/admin callers, not the player route. */
    const parsed = await parseJsonBody<{ policy?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const policy = parsed.value.policy === 'approval' ? 'approval' : parsed.value.policy === 'open' ? 'open' : null;
    if (!policy) return Response.json({ ok: false, error: 'Policy must be open or approval' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setCorporationAdmissionPolicy(repository, { humanId: viewer.id, corporationId: corporationAdmissionMatch[1], policy }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Admission policy update failed' }, { status: 403 });
    }
  }

  const corporationContributionMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/contributions$/);
  if (corporationContributionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const amount = Math.round(Number(body.amount) * 100) / 100;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 10000 || !correlationId) {
      return Response.json({ ok: false, error: 'Contribution amount or correlation ID is invalid' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        contributeToCorporation(repository, { humanId: viewer.id, corporationId: corporationContributionMatch[1], amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation contribution failed';
      return Response.json({ ok: false, error: message }, { status: /membership|required/i.test(message) ? 403 : /insufficient/i.test(message) ? 409 : 400 });
    }
  }

  return null;
}
