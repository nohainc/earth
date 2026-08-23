import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  declarePersonalInsolvencyPostgres,
  recoverInstitutionPostgres,
  settleTaxPostgres,
  publicSpendingPostgres,
} from './finance-postgres.ts';
import { getNetWorthHistory } from './net-worth-postgres.ts';
import { getDailyBriefing } from './daily-briefing-postgres.ts';

export async function handleFinanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, state, machines, businesses] = await Promise.all([
        repository.query("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
        repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
        repository.query("SELECT id, machine_type, condition FROM machines WHERE owner_id = $1 AND machine_type != 'service-robot'", [viewer.id]),
        repository.query('SELECT id, name, status FROM businesses WHERE owner_id = $1', [viewer.id]),
      ]);
      const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
      return {
        account: account.rows[0] ?? null,
        state: stateRow,
        liquidatableAssets: { machines: machines.rows, businesses: businesses.rows },
        protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100), basicServiceRobot: true },
      };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance/personal/declare' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ otp?: string; reason?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) {
      return Response.json({ ok: false, error: 'Authenticator code required for personal insolvency' }, { status: 401 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        declarePersonalInsolvencyPostgres(repository, viewer.id, (body.reason?.trim() || 'Human-requested insolvency restructuring').slice(0, 240)),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Personal insolvency failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/finance' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, rules] = await Promise.all([
        repository.query("SELECT account_id, owner_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
        repository.query('SELECT scope, category, rate, version FROM tax_rules WHERE active = true ORDER BY id'),
      ]);
      return { account: account.rows[0] ?? null, taxRules: rules.rows };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
    const liquidity = (await withRepository(env, (repository) =>
      repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>(
        "SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM account_balances WHERE currency = 'CREDIT') AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index",
      ),
    ))?.rows[0];
    const activeHumans = Number(liquidity?.active_humans ?? 0);
    const supply = Number(liquidity?.money_supply ?? 0);
    const livingCostIndex = Number(liquidity?.living_cost_index ?? 1);
    const target = activeHumans * Math.max(0.5, livingCostIndex) * 100;
    return Response.json({
      activeHumans,
      moneySupply: supply,
      livingCostIndex,
      target,
      corridor: { low: target * 0.8, high: target * 1.2 },
      status: supply < target * 0.8 ? 'below-corridor' : supply > target * 1.2 ? 'above-corridor' : 'inside-corridor',
      persistence: 'planetscale-postgres',
    });
  }

  if (url.pathname === '/api/finance/status' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [states, events] = await Promise.all([
        repository.query('SELECT * FROM financial_states ORDER BY status DESC, institution_kind, institution_id'),
        repository.query('SELECT * FROM bankruptcy_events ORDER BY game_day DESC, created_at DESC LIMIT 50'),
      ]);
      return { states: states.rows, events: events.rows };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance/net-worth-history' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getNetWorthHistory(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to fetch net-worth history';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }

  if (url.pathname === '/api/player/daily-briefing' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getDailyBriefing(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to generate daily briefing';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }

  if (url.pathname === '/api/finance/recover' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ institutionId?: string; amount?: number; otp?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) {
      return Response.json({ ok: false, error: 'Authenticator code required for financial recovery' }, { status: 401 });
    }
    const institutionId = body.institutionId?.trim() ?? '';
    const amount = Math.round(Number(body.amount) * 100) / 100;
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!institutionId || !Number.isFinite(amount) || amount <= 0 || amount > 100000 || !correlationId) {
      return Response.json({ ok: false, error: 'Recovery amount must be between 0 and 100,000 Credits' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        recoverInstitutionPostgres(repository, { humanId: viewer.id, institutionId, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Institution recovery failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : /insufficient|crisis/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname === '/api/taxes/settle' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ taxableAmount?: number }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const taxableAmount = Number(body.taxableAmount);
    if (!Number.isFinite(taxableAmount) || taxableAmount <= 0) {
      return Response.json({ ok: false, error: 'Taxable amount must be positive' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) => settleTaxPostgres(repository, viewer.id, taxableAmount));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Tax settlement failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 409 });
    }
  }

  if (url.pathname === '/api/finance/public-spending' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ cityId?: string; category?: string; amount?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const cityId = body.cityId || 'CITY-0084';
    const category = body.category?.trim() || 'public-services';
    const amount = Number(body.amount);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!Number.isFinite(amount) || amount <= 0 || !correlationId) {
      return Response.json({ ok: false, error: 'Public spending amount and Idempotency-Key are required' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        publicSpendingPostgres(repository, { actorId: viewer.id, cityId, category, amount, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Public spending failed';
      return Response.json({ ok: false, error: message }, { status: /required/i.test(message) ? 403 : /not found/i.test(message) ? 404 : 409 });
    }
  }

  return null;
}
