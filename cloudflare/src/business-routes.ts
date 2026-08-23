import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  createBusinessPostgres,
  liquidateBusinessPostgres,
  distributeDividendsPostgres,
  readBusinessProfilePostgres,
  readBusinessPostgres,
  renameBusinessPostgres,
  setBusinessPolicyPostgres,
  appointManagerPostgres,
  ownershipRegistryPostgres,
  updateConstitutionPostgres,
  transferSharesPostgres,
  issueSharesPostgres,
  hireEmployeePostgres,
  trainEmployeePostgres,
  dismissEmployeePostgres,
  reassignEmployeePostgres,
  proposeMergerPostgres,
  executeMergerPostgres,
} from './business-postgres.ts';

export async function handleBusinessRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  const proposeMergerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/merger\/propose$/);
  if (proposeMergerMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ targetBusinessId?: string; pricePerShare?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const targetBusinessId = body.targetBusinessId?.trim();
    const pricePerShare = Number(body.pricePerShare);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!targetBusinessId || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || !correlationId) {
      return Response.json({ ok: false, error: 'Target business ID, positive price per share, and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        proposeMergerPostgres(repository, { acquirerId: viewer.id, acquirerBusinessId: proposeMergerMatch[1], targetBusinessId, pricePerShare, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Merger proposal failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  const executeMergerMatch = url.pathname.match(/^\/api\/businesses\/merger\/([^/]+)\/execute$/);
  if (executeMergerMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        executeMergerPostgres(repository, { callerId: viewer.id, mergerId: executeMergerMatch[1], correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Merger execution failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/businesses' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; sector?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const sector = body.sector?.trim() ?? 'maintenance';
    const sectors = ['energy', 'extraction', 'components', 'machines', 'maintenance', 'housing', 'compute', 'r-and-d', 'it-services', 'consulting', 'logistics', 'healthcare', 'education'];
    if (!name || name.length < 3 || name.length > 80 || !sectors.includes(sector)) {
      return Response.json({ ok: false, error: 'Business name or sector is invalid' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        createBusinessPostgres(repository, { ownerId: viewer.id, name, sector, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Business registration failed';
      return Response.json({ ok: false, error: message }, { status: /already exists/i.test(message) ? 409 : /requires/i.test(message) ? 409 : 400 });
    }
  }

  const employeeCollectionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/employees$/);
  if (employeeCollectionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; role?: string; wage?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    const wage = Number(body.wage);
    if (!correlationId || !body.name?.trim() || !body.role?.trim() || !Number.isFinite(wage) || wage <= 0) {
      return Response.json({ ok: false, error: 'Employee name, role, wage, and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        hireEmployeePostgres(repository, { humanId: viewer.id, businessId: employeeCollectionMatch[1], name: body.name!, role: body.role!, wage, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Employee hiring failed' }, { status: 409 });
    }
  }

  const employeeActionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/employees\/([^/]+)\/(train|dismiss|reassign)$/);
  if (employeeActionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ role?: string; wage?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
    try {
      const input = { humanId: viewer.id, businessId: employeeActionMatch[1], employeeId: employeeActionMatch[2], correlationId };
      const result = await withRepository(env, (repository) =>
        employeeActionMatch[3] === 'train'
          ? trainEmployeePostgres(repository, input)
          : employeeActionMatch[3] === 'dismiss'
            ? dismissEmployeePostgres(repository, input)
            : reassignEmployeePostgres(repository, { ...input, role: parsed.value.role ?? '', wage: Number(parsed.value.wage) }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Employee action failed' }, { status: 409 });
    }
  }

  const businessLiquidationMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/liquidate$/);
  if (businessLiquidationMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ otp?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid decommission correlationId is required' }, { status: 400 });
    if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) {
      return Response.json({ ok: false, error: 'Authenticator code required for business liquidation' }, { status: 401 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        liquidateBusinessPostgres(repository, { ownerId: viewer.id, businessId: businessLiquidationMatch[1], correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Business liquidation failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /owner|distressed|insolvent/i.test(message) ? 409 : 400 });
    }
  }

  const businessDividendsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/dividends$/);
  if (businessDividendsMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const amount = Number(body.amount);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!Number.isFinite(amount) || amount <= 0 || !correlationId) {
      return Response.json({ ok: false, error: 'A valid positive amount and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        distributeDividendsPostgres(repository, { callerId: viewer.id, businessId: businessDividendsMatch[1], totalAmount: amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Dividend distribution failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|owner|manager/i.test(message) ? 409 : 400 });
    }
  }

  const businessProfileMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)$/);
  if (businessProfileMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => readBusinessProfilePostgres(repository, businessProfileMatch[1], viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    if (result.error) return Response.json({ ok: false, error: result.error }, { status: 403 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  const businessRenameMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/name$/);
  if (businessRenameMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const name = parsed.value.name?.trim() ?? '';
    if (name.length < 2 || name.length > 80) return Response.json({ ok: false, error: 'Business name must be 2–80 characters' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => renameBusinessPostgres(repository, { ownerId: viewer.id, businessId: businessRenameMatch[1], name }));
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business rename failed' }, { status: 409 });
    }
  }

  if ((url.pathname === '/api/businesses/kline-works/policy' || url.pathname === '/api/businesses/me/policy') && request.method === 'POST') {
    const parsed = await parseJsonBody<{ businessId?: string; policy?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!['reliability', 'margin', 'capacity'].includes(body.policy ?? '')) {
      return Response.json({ ok: false, error: 'Unknown business policy' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        setBusinessPolicyPostgres(repository, { humanId: viewer.id, businessId: body.businessId?.trim() || null, policy: body.policy! }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business policy update failed' }, { status: 404 });
    }
  }

  const managerMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/manager$/);
  if (managerMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ managerId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    try {
      const result = await withRepository(env, (repository) =>
        appointManagerPostgres(repository, { ownerId: viewer.id, businessId: managerMatch[1], managerId: body.managerId?.trim() ?? '' }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Manager appointment failed' }, { status: 403 });
    }
  }

  const ownershipRegistryMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/ownership$/);
  if (ownershipRegistryMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => ownershipRegistryPostgres(repository, ownershipRegistryMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business not found' }, { status: 404 });
    }
  }

  const financialsMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/financials$/);
  if (financialsMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => readBusinessPostgres(repository, financialsMatch[1], viewer.id));
    if (result?.business) {
      return Response.json({
        ...result,
        accounting: {
          revenue: 'market-cleared sales and accepted contract income',
          operatingCosts: 'production inputs, maintenance, depreciation, licensing, accepted contract costs, and business tax',
          profit: 'revenue minus operating costs',
        },
        persistence: 'planetscale-postgres',
      });
    }
    return Response.json({ ok: false, error: result?.error ?? 'Business financial statement is not available to this Human' }, { status: 403 });
  }

  const constitutionMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/constitution$/);
  if (constitutionMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) =>
      repository.query(
        'SELECT business_constitutions.*, businesses.name, businesses.owner_id FROM business_constitutions JOIN businesses ON businesses.id = business_constitutions.business_id WHERE business_constitutions.business_id = $1',
        [constitutionMatch[1]],
      ),
    );
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    if (!result.rows[0]) return Response.json({ ok: false, error: 'Business constitution not found' }, { status: 404 });
    return Response.json({
      constitution: result.rows[0],
      management: { ownerId: result.rows[0].owner_id, ownershipAndManagementAreSeparate: true },
      persistence: 'planetscale-postgres',
    });
  }

  if (constitutionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ shareholderVoteThreshold?: number; boardApprovalThreshold?: number; dilutionNoticeDays?: number }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const shareholderVoteThreshold = Number(body.shareholderVoteThreshold ?? 0.5);
    const boardApprovalThreshold = Number(body.boardApprovalThreshold ?? 0.5);
    const dilutionNoticeDays = Number(body.dilutionNoticeDays ?? 3);
    if (![shareholderVoteThreshold, boardApprovalThreshold].every((val) => Number.isFinite(val) && val >= 0.5 && val <= 1) || !Number.isInteger(dilutionNoticeDays) || dilutionNoticeDays < 1 || dilutionNoticeDays > 30) {
      return Response.json({ ok: false, error: 'Constitution thresholds are invalid' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        updateConstitutionPostgres(repository, { ownerId: viewer.id, businessId: constitutionMatch[1], shareholderVoteThreshold, boardApprovalThreshold, dilutionNoticeDays }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Business constitution update failed' }, { status: 403 });
    }
  }

  const shareTransferMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/transfer$/);
  if (shareTransferMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ businessId?: string; recipientId?: string; shares?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const recipientId = body.recipientId?.trim() ?? '';
    const shares = Number(body.shares);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !correlationId) {
      return Response.json({ ok: false, error: 'Invalid share transfer terms' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        transferSharesPostgres(repository, { holderId: viewer.id, businessId: body.businessId?.trim() || null, recipientId, shares, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Share transfer failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  const shareIssueMatch = url.pathname.match(/^\/api\/businesses\/([^/]+)\/shares\/issue$/);
  if (shareIssueMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ recipientId?: string; shares?: number; pricePerShare?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const recipientId = body.recipientId?.trim() ?? '';
    const shares = Number(body.shares);
    const pricePerShare = Math.round(Number(body.pricePerShare) * 100) / 100;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!recipientId || recipientId === viewer.id || !Number.isInteger(shares) || shares < 1 || shares > 10000 || !Number.isFinite(pricePerShare) || pricePerShare <= 0 || pricePerShare > 100000 || !correlationId) {
      return Response.json({ ok: false, error: 'Invalid share issuance terms' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        issueSharesPostgres(repository, { ownerId: viewer.id, businessId: shareIssueMatch[1], recipientId, shares, pricePerShare, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Share issuance failed' }, { status: 409 });
    }
  }

  return null;
}
