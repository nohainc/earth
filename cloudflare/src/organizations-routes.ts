import type { Env } from './index.ts';
import type { ViewerContext } from './auth-session.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { createOrganization, decideOrganizationRequest, joinOrganization, listOrganizationMembers, listOrganizationRequests, listOrganizations } from './organizations-postgres.ts';
import { getOrganizationFinance, provisionOrganizationEconomy, spendOrganizationBudget } from './organization-fiscal-postgres.ts';
import { errorResponse } from './errors.ts';
import { amendOrganizationCharter, getOrganizationCharter, listCharterTemplates } from './organization-charter-postgres.ts';
import { validateOrganizationCharter } from './organization-charter.ts';
import { appointOrganizationOffice, listOrganizationAuthority, resignOrganizationOffice, type OfficeCode } from './organization-authority.ts';
import { distributeOwnership, getAssetOwnership, subscribeToAssetOwnership } from './ownership-postgres.ts';
import { createOrganizationContract, listOrganizationContracts, signOrganizationContract } from './contracts-postgres.ts';

export async function handleOrganizationRoutes(request: Request, env: Env, url: URL, viewer: ViewerContext): Promise<Response | null> {
  if (url.pathname === '/api/organizations/charters/templates' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCharterTemplates(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/organizations' && request.method === 'GET') {
    const archetype = url.searchParams.get('archetype')?.trim().toUpperCase();
    const result = await withRepository(env, (repository) => listOrganizations(repository, viewer.houseId, archetype || undefined));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/organizations' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; archetype?: string; joinPolicy?: string; capabilities?: string[]; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createOrganization(repository, { humanId: viewer.currentHumanId, name: parsed.value.name ?? '', archetype: parsed.value.archetype ?? '', joinPolicy: parsed.value.joinPolicy, capabilities: parsed.value.capabilities, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return errorResponse(error, correlationId, 'Organization formation failed.'); }
  }
  const charterMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/charter(?:\/(history|validate|amend))?$/);
  if (charterMatch && request.method === 'GET' && !charterMatch[2]) {
    try {
      const result = await withRepository(env, (repository) => getOrganizationCharter(repository, charterMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, undefined, 'Organization charter unavailable.'); }
  }
  const authorityMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/authority$/);
  if (authorityMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listOrganizationAuthority(repository, authorityMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  const officeMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/offices\/(EXECUTIVE|TREASURER|GOVERNOR|OPERATOR|RESEARCHER)\/(appoint|resign)$/);
  if (officeMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ targetHumanId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => officeMatch[3] === 'appoint'
        ? appointOrganizationOffice(repository, { organizationId: officeMatch[1], officeCode: officeMatch[2] as OfficeCode, actorHumanId: viewer.currentHumanId, targetHumanId: parsed.value.targetHumanId ?? '', correlationId })
        : resignOrganizationOffice(repository, { organizationId: officeMatch[1], officeCode: officeMatch[2] as OfficeCode, humanId: viewer.currentHumanId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return errorResponse(error, correlationId, 'Organization office operation failed.'); }
  }
  const ownershipMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/assets\/([^/]+)\/ownership$/);
  if (ownershipMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getAssetOwnership(repository, 'BUILDING', ownershipMatch[2]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, organizationId: ownershipMatch[1], ...result, persistence: 'planetscale-postgres' });
  }
  const contractsMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/contracts$/);
  if (contractsMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listOrganizationContracts(repository, contractsMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (contractsMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ counterpartyOrganizationId?: string; templateId?: string; terms?: Record<string, unknown>; startGameDay?: number; endGameDay?: number; amountPerPeriod?: string; periodDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.counterpartyOrganizationId || !parsed.value.templateId || !parsed.value.terms || parsed.value.startGameDay === undefined || parsed.value.endGameDay === undefined || !parsed.value.amountPerPeriod || parsed.value.periodDays === undefined) return Response.json({ ok: false, error: 'Contract parties, template, terms, schedule, amount, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createOrganizationContract(repository, { organizationId: contractsMatch[1], counterpartyOrganizationId: parsed.value.counterpartyOrganizationId!, templateId: parsed.value.templateId!, terms: parsed.value.terms!, startGameDay: parsed.value.startGameDay!, endGameDay: parsed.value.endGameDay!, amountPerPeriod: parsed.value.amountPerPeriod!, periodDays: parsed.value.periodDays!, humanId: viewer.currentHumanId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return errorResponse(error, correlationId, 'Organization contract creation failed.'); }
  }
  const contractSignMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/contracts\/([^/]+)\/sign$/);
  if (contractSignMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => signOrganizationContract(repository, { organizationId: contractSignMatch[1], contractId: contractSignMatch[2], humanId: viewer.currentHumanId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, correlationId, 'Organization contract signature failed.'); }
  }
  if (ownershipMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ investorType?: 'HOUSE' | 'ORGANIZATION'; investorId?: string; units?: string; priceUnits?: string; sourceAccountId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.units || !parsed.value.priceUnits || !parsed.value.sourceAccountId) return Response.json({ ok: false, error: 'Units, price, source account, and idempotency key are required' }, { status: 400 });
    const investorType = parsed.value.investorType ?? 'HOUSE';
    const investorId = parsed.value.investorId ?? viewer.houseId;
    try {
      const result = await withRepository(env, (repository) => subscribeToAssetOwnership(repository, { organizationId: ownershipMatch[1], assetId: ownershipMatch[2], investorType, investorId, units: parsed.value.units!, priceUnits: parsed.value.priceUnits!, sourceAccountId: parsed.value.sourceAccountId!, humanId: viewer.currentHumanId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return errorResponse(error, correlationId, 'Ownership subscription failed.'); }
  }
  const distributionMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/assets\/([^/]+)\/distributions$/);
  if (distributionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ amountUnits?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.amountUnits) return Response.json({ ok: false, error: 'Amount and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => distributeOwnership(repository, { organizationId: distributionMatch[1], assetId: distributionMatch[2], amountUnits: parsed.value.amountUnits!, humanId: viewer.currentHumanId, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, correlationId, 'Ownership distribution failed.'); }
  }
  if (charterMatch && request.method === 'GET' && charterMatch[2] === 'history') {
    const result = await withRepository(env, (repository) => getOrganizationCharter(repository, charterMatch[1], true));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (charterMatch && request.method === 'POST' && charterMatch[2] === 'validate') {
    const parsed = await parseJsonBody<{ charter?: unknown }>(request);
    if (!parsed.ok) return parsed.response;
    try { return Response.json({ ok: true, charter: validateOrganizationCharter(parsed.value.charter) }); }
    catch (error) { return errorResponse(error, undefined, 'Organization charter is invalid.'); }
  }
  if (charterMatch && request.method === 'POST' && charterMatch[2] === 'amend') {
    const parsed = await parseJsonBody<{ charter?: unknown; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || parsed.value.charter === undefined) return Response.json({ ok: false, error: 'Charter and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => amendOrganizationCharter(repository, { organizationId: charterMatch[1], houseId: viewer.houseId, humanId: viewer.currentHumanId, charter: parsed.value.charter, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, correlationId, 'Organization charter amendment failed.'); }
  }
  const memberMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/membership$/);
  if (memberMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => joinOrganization(repository, { humanId: viewer.currentHumanId, organizationId: memberMatch[1], correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.requested ? 202 : 200 });
    } catch (error) { return errorResponse(error, correlationId, 'Organization membership failed.'); }
  }
  const financeMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/finance$/);
  if (financeMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getOrganizationFinance(repository, financeMatch[1], viewer.houseId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, undefined, 'Organization finance unavailable.'); }
  }
  const provisionMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/finance\/provision$/);
  if (provisionMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) => provisionOrganizationEconomy(repository, provisionMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) { return errorResponse(error, undefined, 'Organization economy provisioning failed.'); }
  }
  const spendMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/finance\/spend$/);
  if (spendMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ budgetLineId?: string; sourceAccountType?: 'TREASURY' | 'OPERATIONS'; destinationAccountId?: string; amountUnits?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.budgetLineId || !parsed.value.destinationAccountId || !parsed.value.amountUnits) return Response.json({ ok: false, error: 'Budget line, destination, amount, and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => spendOrganizationBudget(repository, { organizationId: spendMatch[1], houseId: viewer.houseId, budgetLineId: parsed.value.budgetLineId!, sourceAccountType: parsed.value.sourceAccountType ?? 'OPERATIONS', destinationAccountId: parsed.value.destinationAccountId!, amountUnits: parsed.value.amountUnits!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, correlationId, 'Organization budget spend failed.'); }
  }
  const membersMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/members$/);
  if (membersMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listOrganizationMembers(repository, membersMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  const requestMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/requests\/([^/]+)\/(approve|reject)$/);
  const requestsMatch = url.pathname.match(/^\/api\/organizations\/([^/]+)\/requests$/);
  if (requestsMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listOrganizationRequests(repository, requestsMatch[1], viewer.houseId));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, undefined, 'Organization requests unavailable.'); }
  }
  if (requestMatch && request.method === 'POST') {
    const action = requestMatch[3] === 'approve' ? 'APPROVED' : 'REJECTED';
    try {
      const result = await withRepository(env, (repository) => decideOrganizationRequest(repository, { humanId: viewer.currentHumanId, organizationId: requestMatch[1], requestId: requestMatch[2], action }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return errorResponse(error, undefined, 'Organization request decision failed.'); }
  }
  return null;
}
