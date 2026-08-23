import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody } from './request-validation.ts';
import {
  getSuccessorPostgres,
  getLifeStatusPostgres,
  registerSuccessorPostgres,
  settleInheritancePostgres,
} from './lifecycle-postgres.ts';

export async function handleLifecycleRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string; life_status?: string },
): Promise<Response | null> {
  if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getSuccessorPostgres(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/life/status' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getLifeStatusPostgres(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if ((url.pathname === '/api/life/successor' || url.pathname === '/api/successor') && request.method === 'POST') {
    const parsed = await parseJsonBody<{ name?: string; estatePeriodDays?: number; successorHumanId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const successorName = body.name?.trim();
    const estatePeriodDays = Number(body.estatePeriodDays ?? 30);
    if (!successorName || successorName.length < 2) return Response.json({ ok: false, error: 'Successor name is required' }, { status: 400 });
    if (!Number.isInteger(estatePeriodDays) || estatePeriodDays < 7 || estatePeriodDays > 90) {
      return Response.json({ ok: false, error: 'Estate period must be between 7 and 90 days' }, { status: 400 });
    }
    const successorHumanId = body.successorHumanId?.trim() || null;
    try {
      if (viewer.life_status === 'estate') {
        if (!successorHumanId) return Response.json({ ok: false, error: 'An Estate Period requires an existing active Successor Human' }, { status: 400 });
        const world = await withRepository(env, (repository) =>
          repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'"),
        );
        const day = Number(world?.rows[0]?.game_day ?? 0);
        const result = await withRepository(env, (repository) =>
          settleInheritancePostgres(repository, { predecessorId: viewer.id, successorId: successorHumanId, successorName, day }),
        );
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' });
      }
      const result = await withRepository(env, (repository) =>
        registerSuccessorPostgres(repository, { humanId: viewer.id, successorName, estatePeriodDays, successorHumanId, currentLifeStatus: viewer.life_status }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Successor registration failed';
      return Response.json({ ok: false, error: message }, { status: /another active/i.test(message) ? 400 : 409 });
    }
  }

  return null;
}
