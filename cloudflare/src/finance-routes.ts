import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  recoverInstitution as recoverInstitutionPostgres,
  publicSpending as publicSpendingPostgres,
} from './finance-postgres.ts';
import { getNetWorthHistory } from './net-worth-postgres.ts';
import { getDailyBriefing } from './daily-briefing-postgres.ts';
import { createBankDeposit, listBankDeposits, withdrawBankDeposit } from './global-bank-postgres.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';

export async function handleFinanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string; house_id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (url.pathname === '/api/finance/me' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [accounts, summary, state, claims, deposits, entries] = await Promise.all([
        repository.query(`SELECT a.id AS account_id, ea.code AS asset_code, a.asset_id, a.account_type, a.balance::TEXT AS balance_units,
                                 ea.scale, ea.decimals
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                            LEFT JOIN economic_assets ea ON ea.id = a.asset_id
                           WHERE o.id = $1 AND a.status = 'active' ORDER BY a.asset_id, a.account_type`, [viewer.house_id]),
        repository.query(`SELECT s.* FROM owner_financial_summary s JOIN owner_registry o ON o.economic_id = s.owner_economic_id WHERE o.id = $1`, [viewer.house_id]),
        repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
        repository.query(`SELECT obligation_type, principal_due_units, interest_due_units, due_game_day, priority_class, status
                            FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id
                           WHERE o.id = $1 ORDER BY due_game_day, priority_class`, [viewer.house_id]),
        repository.query(`SELECT id, principal_units, accrued_interest_units, rate_bps, maturity_total_game_minute, status,
                                 deposit_protection_limit_units, deposit_protection_rule_version
                            FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
                           WHERE o.id = $1 ORDER BY created_at DESC`, [viewer.house_id]),
        repository.query(`SELECT t.id, t.game_day, t.game_minute, t.transaction_kind, t.correlation_id,
                                 e.asset_id, e.delta, e.reason_code
                            FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id
                           WHERE e.account_id IN (SELECT a.id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1)
                           ORDER BY t.id DESC LIMIT 100`, [viewer.house_id]),
      ]);
      return { accounts: accounts.rows, summary: summary.rows[0] ?? null, state: state.rows[0] ?? null, obligations: claims.rows, deposits: deposits.rows, transactions: entries.rows };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/taxes' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query(`SELECT f.* FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id WHERE o.id = $1 AND f.obligation_type = 'TAX' ORDER BY f.due_game_day DESC`, [viewer.house_id]));
    return Response.json({ obligations: result?.rows ?? [], persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/bank/balance-sheet' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query('SELECT * FROM global_bank_balance_sheet ORDER BY game_day DESC LIMIT 1'));
    return Response.json({ balanceSheet: result?.rows[0] ?? null, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/bank' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [state, sheet, deposits] = await Promise.all([
        repository.query('SELECT * FROM global_bank_resolution_state WHERE id = 1'),
        repository.query('SELECT * FROM global_bank_balance_sheet ORDER BY game_day DESC LIMIT 1'),
        repository.query(`SELECT d.* FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id WHERE o.id = $1 ORDER BY d.created_at DESC`, [viewer.house_id]),
      ]);
      return { resolution: state.rows[0] ?? null, balanceSheet: sheet.rows[0] ?? null, deposits: deposits.rows };
    });
    return Response.json({ ...(result ?? {}), persistence: 'planetscale-postgres' });
  }
  if (url.pathname.startsWith('/api/finance/institutions/') && request.method === 'GET') {
    const institutionId = url.pathname.split('/').pop() ?? '';
    const result = await withRepository(env, async (repository) => {
      const [accounts, state, obligations, financialProjection] = await Promise.all([
        repository.query(`SELECT a.id AS account_id, ea.code AS asset_code, a.asset_id, a.account_type, a.balance::TEXT AS balance_units
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id LEFT JOIN economic_assets ea ON ea.id = a.asset_id
                           WHERE o.id = $1 AND a.status = 'active' ORDER BY a.asset_id, a.account_type`, [institutionId]),
        repository.query('SELECT * FROM financial_states WHERE institution_id = $1', [institutionId]),
        repository.query(`SELECT f.* FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id WHERE o.id = $1`, [institutionId]),
        repository.query('SELECT * FROM institution_financial_projections WHERE institution_id = $1', [institutionId]),
      ]);
      return { institutionId, accounts: accounts.rows, state: state.rows[0] ?? null, financialProjection: financialProjection.rows[0] ?? null, obligations: obligations.rows };
    });
    return Response.json({ ...(result ?? {}), persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/monetary-supply' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => repository.query('SELECT * FROM monetary_supply_snapshots ORDER BY game_day DESC LIMIT 1'));
    return Response.json({ snapshot: result?.rows[0] ?? null, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/bank/deposits' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listBankDeposits(repository, viewer.id));
    return Response.json({ ...(result ?? { deposits: [] }), persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/bank/deposit' && request.method === 'POST') {
    if (!featureEnabled(env, 'bankDeposits')) return featureDisabledResponse('bankDeposits');
    const parsed = await parseJsonBody<{ amount?: number; termDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Correlation ID is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createBankDeposit(repository, { humanId: viewer.id, amount: Number(parsed.value.amount ?? 0), termDays: Number(parsed.value.termDays ?? 7), correlationId }));
      return Response.json({ ...(result ?? { ok: false }), persistence: 'planetscale-postgres' }, { status: result?.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Bank deposit failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/finance/bank/withdraw' && request.method === 'POST') {
    if (!featureEnabled(env, 'bankDeposits')) return featureDisabledResponse('bankDeposits');
    const parsed = await parseJsonBody<{ depositId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const depositId = parsed.value.depositId?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!depositId || !correlationId) return Response.json({ ok: false, error: 'Deposit ID and correlation ID are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => withdrawBankDeposit(repository, { humanId: viewer.id, depositId, correlationId }));
      return Response.json({ ...(result ?? { ok: false }), persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Bank withdrawal failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, state, buildings, context, latestMaintenance, arrears, taxRules, taxObligations, bankDeposits, transactions] = await Promise.all([
        repository.query(`SELECT a.id::TEXT AS account_id, a.balance::TEXT AS balance_units,
                                 (a.balance / 100.0) AS balance, 'CREDIT' AS currency,
                                 a.account_type, a.is_default_settlement
                            FROM economic_accounts a
                            JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                           WHERE o.id = $1 AND a.asset_id = 1 AND a.status = 'active'
                           ORDER BY a.is_default_settlement DESC, a.account_type`, [viewer.house_id]),
        repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
        repository.query("SELECT b.id, b.name, b.building_type, b.status FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE o.id = $1 AND b.ownership_class = 'private'", [viewer.house_id]),
        repository.query<{ age_years: number; city_id: string | null; living_cost_index: string }>("SELECT h.age_years, ha.city_id, w.living_cost_index FROM humans h LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE' CROSS JOIN world_state w WHERE h.id = $1 AND w.id = 'WORLD'", [viewer.id]),
        repository.query('SELECT game_day, food_used, energy_used, compute_used, credits_for_resources, life_condition_after, shortfall_notes, paid, unpaid, status FROM personal_life_maintenance WHERE human_id = $1 ORDER BY game_day DESC LIMIT 1', [viewer.id]),
        repository.query<{ total: string }>('SELECT COALESCE(SUM(unpaid), 0) AS total FROM personal_life_maintenance WHERE human_id = $1', [viewer.id]),
        repository.query(`SELECT DISTINCT ON (tax_rule_id) id, tax_rule_id, scope, category, rate_bps, version,
                                 tax_base_definition, beneficiary_economic_id, effective_from_game_day, effective_to_game_day
                            FROM tax_rule_versions
                           WHERE effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
                             AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
                           ORDER BY tax_rule_id, effective_from_game_day DESC, version DESC`),
        repository.query('SELECT id, tax_type, tax_base_units, rate_bps, amount_units, rule_version, game_day, status, due_game_day FROM tax_obligations t JOIN owner_registry o ON o.economic_id = t.taxpayer_economic_id WHERE o.id = $1 ORDER BY t.game_day DESC, t.id DESC', [viewer.house_id]),
        repository.query(`SELECT d.id, d.principal_units, d.accrued_interest_units, d.rate_bps, d.rate_rule_version,
                                 d.start_total_game_minute, d.maturity_total_game_minute, d.status,
                                 d.created_transaction_id, d.payout_transaction_id, d.correlation_id
                            FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
                           WHERE o.id = $1 ORDER BY d.created_at DESC`, [viewer.house_id]),
        repository.query(`SELECT t.id, t.game_day, t.game_minute, t.transaction_kind, t.correlation_id,
                                 e.asset_id, e.delta, e.reason_code
                            FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id
                           WHERE e.account_id IN (SELECT a.id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1)
                           ORDER BY t.id DESC LIMIT 100`, [viewer.house_id]),
      ]);
      const stateRow = state.rows[0] ?? { status: 'active', protected_credits: 100 };
      const resident = context.rows[0];
      return {
        account: account.rows[0] ?? null,
        state: stateRow,
        liquidatableAssets: { buildings: buildings.rows, businesses: [] },
        protectedMinimum: { credits: Number(stateRow.protected_credits ?? 100) },
        lifeMaintenance: { lastSettlement: latestMaintenance.rows[0] ?? null, unpaidTotal: Number(arrears.rows[0]?.total ?? 0), cityId: resident?.city_id ?? null },
        taxes: { rules: taxRules.rows, obligations: taxObligations.rows },
        bank: { deposits: bankDeposits.rows },
        transactions: transactions.rows,
      };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, rules] = await Promise.all([
        repository.query(`SELECT a.id::TEXT AS account_id, o.id AS owner_id, (a.balance / 100.0) AS balance, 'CREDIT' AS currency
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                           WHERE o.id = $1 AND a.asset_id = 1 AND a.is_default_settlement AND a.status = 'active'`, [viewer.house_id]),
        repository.query(`SELECT DISTINCT ON (tax_rule_id) tax_rule_id AS id, scope, category, rate_bps, version,
                                 tax_base_definition, effective_from_game_day, effective_to_game_day
                            FROM tax_rule_versions
                           WHERE effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
                             AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
                           ORDER BY tax_rule_id, effective_from_game_day DESC, version DESC`),
      ]);
      return { account: account.rows[0] ?? null, taxRules: rules.rows };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
    const liquidity = (await withRepository(env, (repository) =>
      repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>(
        "SELECT (SELECT COUNT(*) FROM humans WHERE life_status = 'active') AS active_humans, (SELECT COALESCE(SUM(balance), 0) FROM economic_accounts WHERE asset_id = 1 AND account_type NOT IN (7, 8) AND status = 'active') / 100.0 AS money_supply, (SELECT living_cost_index FROM world_state WHERE id = 'WORLD') AS living_cost_index",
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
    const cityId = body.cityId?.trim();
    const category = body.category?.trim() || 'public-services';
    const amount = Number(body.amount);
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!cityId || !Number.isFinite(amount) || amount <= 0 || !correlationId) {
      return Response.json({ ok: false, error: 'City ID, public spending amount, and Idempotency-Key are required' }, { status: 400 });
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
