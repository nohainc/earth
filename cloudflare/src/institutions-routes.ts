import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listCitiesPostgres,
  createCityPostgres,
  cityQualificationPostgres,
  listCorporationsPostgres,
  createCorporationWithCapitalPostgres,
  createCorporationPostgres,
  corporationQualificationPostgres,
  setCityBudgetPostgres,
  setCityTaxCharterPostgres,
  setCorporationTaxCharterPostgres,
  adoptCityForCorporationPostgres,
  changeCorporationMembershipPostgres,
  setCorporationAdmissionPolicyPostgres,
  decideCorporationMembershipRequestPostgres,
  changeCityResidencyPostgres,
  spendCorporationTreasuryPostgres,
  contributeToCorporationPostgres,
} from './institutions-postgres.ts';

export async function handleInstitutionRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/cities' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCitiesPostgres(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/cities' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; communityId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const communityId = body.communityId?.trim() || null;
    if (!name || name.length < 3 || name.length > 80) {
      return Response.json({ ok: false, error: 'A city name is required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCityPostgres(repository, { founderId: viewer.id, communityId, name }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'City formation failed';
      return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
    }
  }

  const cityQualificationMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/qualification$/);
  if (cityQualificationMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => cityQualificationPostgres(repository, cityQualificationMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'City qualification unavailable' }, { status: 404 });
    }
  }

  if (url.pathname === '/api/corporations' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCorporationsPostgres(repository, url.searchParams.get('search') ?? ''));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/corporations/with-capital' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ corporationName?: string; cityName?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const corporationName = parsed.value.corporationName?.trim();
    const cityName = parsed.value.cityName?.trim();
    if (!corporationName || !cityName) {
      return Response.json({ ok: false, error: 'Corporation and capital city names are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCorporationWithCapitalPostgres(repository, { founderId: viewer.id, corporationName, cityName }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation formation failed';
      return Response.json({ ok: false, error: message }, { status: /already|leave|exists/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/corporations' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; cityId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const cityId = body.cityId?.trim();
    if (!name || name.length < 3 || name.length > 80 || !cityId) {
      return Response.json({ ok: false, error: 'Corporation name and founding City are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createCorporationPostgres(repository, { founderId: viewer.id, cityId, name }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation formation failed';
      return Response.json({ ok: false, error: message }, { status: /founder|not found/i.test(message) ? 403 : /requires|exists/i.test(message) ? 409 : 400 });
    }
  }

  const corporationQualificationMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/qualification$/);
  if (corporationQualificationMatch && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => corporationQualificationPostgres(repository, corporationQualificationMatch[1]));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Corporation qualification unavailable' }, { status: 404 });
    }
  }

  const cityBudgetMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/budget$/);
  if (cityBudgetMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ category?: string; amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const category = body.category?.trim();
    const amount = Number(body.amount);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!category || !Number.isFinite(amount) || amount < 0 || !correlationId) {
      return Response.json({ ok: false, error: 'A valid budget category, amount, and correlation ID are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        setCityBudgetPostgres(repository, { humanId: viewer.id, cityId: cityBudgetMatch[1], category, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'City budget update failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
    }
  }

  const cityTaxCharterMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/tax-charter$/);
  if (cityTaxCharterMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ incomeTaxBps?: number; salesTaxBps?: number; corporateTaxBps?: number; propertyTaxBps?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setCityTaxCharterPostgres(repository, {
          humanId: viewer.id,
          cityId: cityTaxCharterMatch[1],
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
      const message = error instanceof Error ? error.message : 'Tax charter update failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
    }
  }

  const corporationTaxCharterMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/tax-charter$/);
  if (corporationTaxCharterMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ incomeTaxBps?: number; salesTaxBps?: number; corporateTaxBps?: number; propertyTaxBps?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid correlation ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setCorporationTaxCharterPostgres(repository, {
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

  const corporationCityMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/cities\/([^/]+)$/);
  if (corporationCityMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) =>
        adoptCityForCorporationPostgres(repository, { humanId: viewer.id, corporationId: corporationCityMatch[1], cityId: corporationCityMatch[2] }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation city adoption failed';
      return Response.json({ ok: false, error: message }, { status: /required|another corporation|include members/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 400 });
    }
  }

  const corporationMembershipMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/membership$/);
  if (corporationMembershipMatch && (request.method === 'POST' || request.method === 'DELETE')) {
    try {
      const result = await withRepository(env, (repository) =>
        changeCorporationMembershipPostgres(repository, {
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
    const parsed = await parseJsonBody<{ policy?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const policy = parsed.value.policy === 'approval' ? 'approval' : parsed.value.policy === 'open' ? 'open' : null;
    if (!policy) return Response.json({ ok: false, error: 'Policy must be open or approval' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        setCorporationAdmissionPolicyPostgres(repository, { humanId: viewer.id, corporationId: corporationAdmissionMatch[1], policy }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Admission policy update failed' }, { status: 403 });
    }
  }

  const corporationRequestMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/membership-requests\/([^/]+)$/);
  if (corporationRequestMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ decision?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const decision = parsed.value.decision === 'approved' ? 'approved' : parsed.value.decision === 'rejected' ? 'rejected' : null;
    if (!decision) return Response.json({ ok: false, error: 'Decision must be approved or rejected' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        decideCorporationMembershipRequestPostgres(repository, { humanId: viewer.id, corporationId: corporationRequestMatch[1], requestId: corporationRequestMatch[2], decision }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Membership request decision failed' }, { status: 403 });
    }
  }

  const residencyMatch = url.pathname.match(/^\/api\/cities\/([^/]+)\/residency$/);
  if (residencyMatch && (request.method === 'POST' || request.method === 'DELETE')) {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const dayKey = request.method === 'POST' ? '' : 'leave';
    const correlationId = body.correlationId?.trim() || `RESIDENCY-${viewer.id}-${residencyMatch[1]}-${request.method}-${dayKey}`;
    if (correlationId.length > 120) return Response.json({ ok: false, error: 'Correlation ID is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        changeCityResidencyPostgres(repository, { humanId: viewer.id, cityId: residencyMatch[1], action: request.method === 'POST' ? 'join' : 'leave', correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'City residency change failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /already|resident/i.test(message) ? 409 : 400 });
    }
  }

  const corporationSpendMatch = url.pathname.match(/^\/api\/corporations\/([^/]+)\/treasury\/spend$/);
  if (corporationSpendMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ category?: string; amount?: number; cityId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const amount = Number(body.amount);
    const category = body.category?.trim() || 'public-services';
    const cityId = body.cityId?.trim() || 'CITY-0084';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 100000 || !correlationId) {
      return Response.json({ ok: false, error: 'Treasury amount and correlation ID are invalid' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        spendCorporationTreasuryPostgres(repository, { humanId: viewer.id, corporationId: corporationSpendMatch[1], cityId, category, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Corporation treasury spending failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient/i.test(message) ? 409 : 400 });
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
        contributeToCorporationPostgres(repository, { humanId: viewer.id, corporationId: corporationContributionMatch[1], amount, correlationId }),
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
