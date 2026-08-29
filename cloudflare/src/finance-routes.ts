import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  recoverInstitution as recoverInstitutionPostgres,
  publicSpending as publicSpendingPostgres,
} from './finance-postgres.ts';
import { getNetWorthHistory } from './net-worth-postgres.ts';
import { getDailyBriefing } from './daily-briefing-postgres.ts';
import { estimateLifeMaintenance } from './life-maintenance-postgres.ts';
import { fromNanoMarkup } from './nano-markup.ts';

function charterRate(raw: unknown, key: string): number | null {
  const charter = fromNanoMarkup<Record<string, unknown>>(raw);
  const value = Number(charter?.[key]);
  return Number.isFinite(value) ? value / 10000 : null;
}

export async function handleFinanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, state, buildings, businesses, context, latestMaintenance, arrears, basicRule, businessIncome, buildingOutput, dividends, allTaxRules, paidTaxes, taxPayments, dailyProfile] = await Promise.all([
        repository.query("SELECT account_id, balance, currency FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [viewer.id]),
        repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
        repository.query("SELECT id, name, building_type, condition, status FROM buildings WHERE owner_id = $1 AND ownership_class = 'private'", [viewer.id]),
        repository.query('SELECT id, name, status FROM businesses WHERE owner_id = $1', [viewer.id]),
        repository.query<{ age_years: number; city_id: string | null; residents: string | null; housing_capacity: string | null; energy_capacity: string | null; connectivity_capacity: string | null; health_capacity: string | null; living_cost_index: string; city_charter: string | null; corporation_charter: string | null }>("SELECT h.age_years, m.city_id, c.residents, c.housing_capacity, c.energy_capacity, c.connectivity_capacity, c.health_capacity, w.living_cost_index, city_institution.charter_rules AS city_charter, corporation_institution.charter_rules AS corporation_charter FROM humans h CROSS JOIN world_state w LEFT JOIN memberships m ON m.human_id = h.id LEFT JOIN cities c ON c.id = m.city_id LEFT JOIN institutions city_institution ON city_institution.id = m.city_id LEFT JOIN institutions corporation_institution ON corporation_institution.id = m.corporation_id WHERE h.id = $1 AND w.id = 'WORLD'", [viewer.id]),
        repository.query('SELECT game_day, food_used, energy_used, compute_used, credits_for_resources, life_condition_after, shortfall_notes, paid, unpaid, status FROM personal_life_maintenance WHERE human_id = $1 ORDER BY game_day DESC LIMIT 1', [viewer.id]),
        repository.query<{ total: string }>('SELECT COALESCE(SUM(unpaid), 0) AS total FROM personal_life_maintenance WHERE human_id = $1', [viewer.id]),
        repository.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true", []),
        repository.query<{ profit: string }>("SELECT COALESCE(SUM(f.profit), 0) AS profit FROM businesses b LEFT JOIN business_financials f ON f.business_id = b.id WHERE b.owner_id = $1 AND b.status = 'active'", [viewer.id]),
        repository.query("SELECT resource_output_type, resource_output_amount, daily_operating_credits, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, operating_policy, condition, auto_repair_enabled, ownership_class FROM buildings WHERE owner_id = $1 AND ownership_class = 'private' AND status = 'active'", [viewer.id]),
        repository.query<{ amount: string }>("SELECT COALESCE(SUM(GREATEST(0, b.resource_output_amount * CASE WHEN b.operating_policy = 'high_output' THEN 1.3 WHEN b.operating_policy IN ('frugal','eco_reserve') THEN .75 ELSE 1 END - b.daily_operating_credits * CASE WHEN b.operating_policy = 'high_output' THEN 1.4 WHEN b.operating_policy IN ('frugal','eco_reserve') THEN .7 ELSE 1 END) * s.shares_owned / GREATEST(1, s.total_shares_issued)), 0) AS amount FROM building_investment_shares s JOIN buildings b ON b.id = s.building_id WHERE s.investor_id = $1 AND b.ownership_class = 'public_investment' AND b.status = 'active'", [viewer.id]),
        repository.query<{ id: string; category: string; rate: string }>('SELECT id, category, rate FROM tax_rules WHERE active = true ORDER BY id'),
        repository.query<{ amount: string }>("SELECT COALESCE(SUM(amount), 0) AS amount FROM ledger_entries WHERE debit_account = (SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' LIMIT 1) AND game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD') AND reason_type IN ('basic_levy','business_tax_city','business_tax_corp','business_tax_ouc','market_tax')", [viewer.id]),
        repository.query<{ category: string; amount: string }>("SELECT CASE WHEN reason_type = 'basic_levy' THEN 'basic_income' WHEN reason_type LIKE 'business_tax%' THEN 'business' WHEN reason_type = 'market_tax' THEN 'market' END AS category, COALESCE(SUM(amount), 0) AS amount FROM ledger_entries WHERE debit_account = (SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' LIMIT 1) AND game_day = (SELECT game_day FROM world_state WHERE id = 'WORLD') AND reason_type IN ('basic_levy','business_tax_city','business_tax_corp','business_tax_ouc','market_tax') GROUP BY 1", [viewer.id]),
        repository.query('SELECT owner_kind, profile_version, status, effective_game_day, last_settled_game_day, credits_delta, energy_delta, food_delta, materials_delta, components_delta, compute_delta FROM daily_settlement_profiles WHERE owner_id = $1', [viewer.id]),
      ]);
      const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
      const resident = context.rows[0];
      const maintenance = resident ? estimateLifeMaintenance(resident, Number(resident.living_cost_index ?? 1)) : null;
      const cityRate = charterRate(resident?.city_charter, 'incomeTaxBps');
      const corporationRate = charterRate(resident?.corporation_charter, 'incomeTaxBps');
      const baseRate = Number(basicRule.rows[0]?.rate ?? 0);
      const taxRate = cityRate ?? corporationRate ?? baseRate;
      const taxSource = cityRate !== null ? 'City' : corporationRate !== null ? 'Corporation' : 'Earth';
      const estimatedDailyLevy = Math.round(100 * Math.max(0.5, Math.min(3, Number(resident?.living_cost_index ?? 1))) * taxRate * 100) / 100;
      return {
        account: account.rows[0] ?? null,
        state: stateRow,
        liquidatableAssets: { buildings: buildings.rows, businesses: businesses.rows },
        protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100) },
        lifeMaintenance: {
          nextDailyCost: maintenance,
          lastSettlement: latestMaintenance.rows[0] ?? null,
          unpaidTotal: Number(arrears.rows[0]?.total ?? 0),
          cityId: resident?.city_id ?? null,
        },
        basicLevy: { rate: taxRate, source: taxSource, version: basicRule.rows[0]?.version ?? null, estimatedDailyLevy },
        taxes: { rules: allTaxRules.rows.map((row) => ({ ...row, rate: Number(row.rate) })), paidToday: Number(paidTaxes.rows[0]?.amount ?? 0), payments: Object.fromEntries(taxPayments.rows.map((row) => [row.category, Number(row.amount)])) },
        assetIncome: { businessProfit: Number(businessIncome.rows[0]?.profit ?? 0), privateBuildings: buildingOutput.rows, civicDividends: Number(dividends.rows[0]?.amount ?? 0) },
        dailyProfile: dailyProfile.rows[0] ? Object.fromEntries(Object.entries(dailyProfile.rows[0]).map(([key, value]) => [key, typeof value === 'string' && /^-?\\d+(?:\\.\\d+)?$/.test(value) ? Number(value) : value])) : null,
      };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
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
