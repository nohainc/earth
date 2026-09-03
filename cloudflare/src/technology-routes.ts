import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listTechnologyPostgres,
  adoptTechnologyPostgres,
  createResearchProjectPostgres,
  fundResearchProjectPostgres,
  grantPatent as grantPatentPostgres,
  licenseTechnology as licenseTechnologyPostgres,
} from './technology-postgres.ts';
import {
  listCorporationBuildingResearch,
  startCorporationBuildingResearch,
} from './corporation-building-research-postgres.ts';

export async function handleTechnologyRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (url.pathname.endsWith('/patent') || url.pathname.endsWith('/license')) {
    return Response.json({ ok: false, error: 'Patents and technology licensing have been retired' }, { status: 404 });
  }
  if (url.pathname === '/api/technology' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listTechnologyPostgres(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/corporation/building-research' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listCorporationBuildingResearch(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/corporation/building-research' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ buildingType?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const buildingType = parsed.value.buildingType?.trim();
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!buildingType || !correlationId) return Response.json({ ok: false, error: 'Building type and Idempotency-Key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => startCorporationBuildingResearch(repository, { humanId: viewer.id, buildingType, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Building research failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/technology/adopt' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ businessId?: string; technologyId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const businessId = parsed.value.businessId?.trim();
    const technologyId = parsed.value.technologyId?.trim();
    if (!businessId || !technologyId) return Response.json({ ok: false, error: 'Business and technology are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        adoptTechnologyPostgres(repository, { humanId: viewer.id, businessId, technologyId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Technology adoption failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/technology/projects' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; budget?: number; focus?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const name = body.name?.trim();
    const budget = Math.round(Number(body.budget ?? 240) * 100) / 100;
    const focus = body.focus?.trim() ?? 'efficiency';
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!name || name.length < 3 || name.length > 120 || !Number.isFinite(budget) || budget < 240 || budget > 100000 || !['efficiency', 'durability', 'safety', 'cost'].includes(focus) || !correlationId) {
      return Response.json({ ok: false, error: 'Research parameters or Idempotency-Key are invalid' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        createResearchProjectPostgres(repository, { ownerId: viewer.id, name, budget, focus, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Research project creation failed' }, { status: 409 });
    }
  }

  if ((url.pathname === '/api/technology/TECH-001/fund' || url.pathname === '/api/technology/me/fund') && request.method === 'POST') {
    const parsed = await parseJsonBody<{ amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const amount = Number(body.amount ?? 240);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!Number.isFinite(amount) || amount <= 0 || !correlationId) {
      return Response.json({ ok: false, error: 'Funding parameters or Idempotency-Key are invalid' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        fundResearchProjectPostgres(repository, { ownerId: viewer.id, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Research funding failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if ((url.pathname === '/api/technology/TECH-001/patent' || url.pathname === '/api/technology/me/patent') && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) => grantPatentPostgres(repository, { ownerId: viewer.id }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Patent grant failed' }, { status: 409 });
    }
  }

  if ((url.pathname === '/api/technology/TECH-001/license' || url.pathname === '/api/technology/me/license') && request.method === 'POST') {
    const parsed = await parseJsonBody<{ licenseeId?: string; licenseeBusinessId?: string; royaltyRate?: number; licenseFee?: number; otp?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const licenseeId = body.licenseeId || viewer.id;
    const royaltyRate = Number(body.royaltyRate ?? 0.05);
    const licenseFee = Number(body.licenseFee ?? 100);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    if (!licenseeId || !Number.isFinite(royaltyRate) || royaltyRate < 0.01 || royaltyRate > 0.5 || !Number.isFinite(licenseFee) || licenseFee < 0) {
      return Response.json({ ok: false, error: 'Licensing parameters are invalid' }, { status: 400 });
    }
    if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) {
      return Response.json({ ok: false, error: 'Authenticator code required for technology licensing' }, { status: 401 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        licenseTechnologyPostgres(repository, { licensorId: viewer.id, licenseeId, licenseeBusinessId: body.licenseeBusinessId, royaltyRate, licenseFee, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Technology licensing failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  return null;
}
