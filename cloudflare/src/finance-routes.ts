import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import { getCorporationFiscalState, spendCorporationBudget } from './corporation-fiscal-postgres.ts';
import { getNetWorthHistory } from './net-worth-postgres.ts';
import { createBankDeposit, getBankDepositQuote, listBankDeposits, withdrawBankDeposit } from './global-bank-postgres.ts';
import { parseCreditAmount } from './money.ts';
import { featureDisabledResponse, featureEnabled } from './feature-config.ts';
import { getFinancialQuote } from './financial-quotes.ts';
import { getHouseFinancialProjection, getInstitutionFinancialProjection } from './financial-projections.ts';
import { addBankLoanGuarantee, getBankLoanQuote, getBankRiskProjection, listBankLoans, originateBankLoan, repayBankLoan } from './banking-postgres.ts';
import { createOrganizationResolutionCase, getOrganizationFinancialState } from './organization-stress-postgres.ts';
import { getTaxStatement } from './tax-statement-postgres.ts';
import { getV5HouseCapacity } from './v5-capacity-postgres.ts';
import { listV5CapacityResolutionCases, liquidateV5HouseBuilding, openV5CapacityResolutionCase } from './v5-capacity-resolution-postgres.ts';
import { listV5CorporationReceivershipCases, submitV5CorporationRestructuringPlan } from './v5-corporation-receivership-postgres.ts';
import { isSettlementBarrierError } from './settlement-barrier-postgres.ts';
import { getHouseFinanceOverview } from './house-finance-overview-postgres.ts';

export async function handleFinanceRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string; house_id: string },
  sensitiveActionAllowed: (env: Env, humanId: string, otp?: string) => Promise<boolean>,
): Promise<Response | null> {
  if (url.pathname === '/api/v5/house/capacity-resolution' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listV5CapacityResolutionCases(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }
  const v5Receivership = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/receivership$/);
  if (v5Receivership && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => listV5CorporationReceivershipCases(repository, { humanId: viewer.id, corporationId: v5Receivership[1] }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Receivership history unavailable' }, { status: 403 }); }
  }
  const v5Restructure = url.pathname.match(/^\/api\/v5\/corporations\/([^/]+)\/receivership\/([^/]+)\/restructure$/);
  if (v5Restructure && request.method === 'POST') {
    const parsed = await parseJsonBody<{ planText?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.planText) return Response.json({ ok: false, error: 'A restructuring plan and idempotency key are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => submitV5CorporationRestructuringPlan(repository, { humanId: viewer.id, corporationId: v5Restructure[1], caseId: v5Restructure[2], planText: parsed.value.planText!, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Restructuring plan submission failed' }, { status: 409 }); }
  }
  if (url.pathname === '/api/v5/house/capacity-resolution' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ reason?: string }>(request);
    if (!parsed.ok) return parsed.response;
    try {
      const result = await withRepository(env, (repository) => openV5CapacityResolutionCase(repository, { humanId: viewer.id, reason: parsed.value.reason }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Capacity resolution case could not be opened' }, { status: 409 }); }
  }
  const v5Liquidation = url.pathname.match(/^\/api\/v5\/house\/capacity-resolution\/([^/]+)\/liquidate\/([^/]+)$/);
  if (v5Liquidation && request.method === 'POST') {
    const parsed = await parseJsonBody<{ correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'A valid idempotency key is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => liquidateV5HouseBuilding(repository, { humanId: viewer.id, caseId: v5Liquidation[1], buildingId: v5Liquidation[2], correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Capacity asset release failed' }, { status: 409 }); }
  }

  if (url.pathname === '/api/finance/tax-statement' && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getTaxStatement(repository, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Tax statement unavailable' }, { status: 400 }); }
  }
  if (url.pathname === '/api/finance/projection' && request.method === 'GET') {
    const scope = url.searchParams.get('scope')?.trim().toUpperCase() ?? 'HOUSE';
    try {
      const result = await withRepository(env, async (repository) => {
        if (scope === 'HOUSE') return getHouseFinancialProjection(repository, viewer.house_id);
        if (scope === 'EARTH') return getInstitutionFinancialProjection(repository, 'EARTH');
        if (scope === 'CORPORATION') {
          const corporation = (await repository.query<{ corporation_id: string }>("SELECT corporation_id FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE' LIMIT 1", [viewer.house_id])).rows[0];
          if (!corporation) throw new Error('Active Corporation affiliation not found');
          return getInstitutionFinancialProjection(repository, corporation.corporation_id);
        }
        throw new Error('Unknown financial projection scope');
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ projection: result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Financial projection unavailable' }, { status: 400 }); }
  }
  if (url.pathname === '/api/finance/quote' && request.method === 'GET') {
    const quoteType = url.searchParams.get('quoteType')?.trim().toUpperCase() as Parameters<typeof getFinancialQuote>[1]['quoteType'];
    if (!quoteType) return Response.json({ ok: false, error: 'Quote type is required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => getFinancialQuote(repository, {
        quoteType,
        ownerId: viewer.id,
        territoryId: url.searchParams.get('territoryId')?.trim() || undefined,
        buildingType: url.searchParams.get('buildingType')?.trim() || undefined,
        technologyId: url.searchParams.get('technologyId')?.trim() || undefined,
        licenseId: url.searchParams.get('licenseId')?.trim() || undefined,
      }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ quote: result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Financial quote unavailable' }, { status: 400 }); }
  }
  if ((url.pathname === '/api/finance/overview' || url.pathname === '/api/finance/me' || url.pathname === '/api/finance/personal') && request.method === 'GET') {
    try {
      const result = await withRepository(env, (repository) => getHouseFinanceOverview(repository, viewer.house_id, viewer.id));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      const headers = new Headers({ 'Content-Type': 'application/json' });
      if (url.pathname !== '/api/finance/overview') {
        headers.set('Deprecation', 'true');
        headers.set('Link', '</api/finance/overview>; rel="successor-version"');
      }
      return new Response(JSON.stringify({ ...result, persistence: 'planetscale-postgres' }), { headers });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'House finance overview unavailable' }, { status: 400 });
    }
  }
  if (url.pathname === '/api/finance/me' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [accounts, deposits, entries, taxStatement] = await Promise.all([
        repository.query(`SELECT a.id AS account_id, ea.code AS asset_code, a.asset_id, a.account_type,
                                 a.balance_units::TEXT AS balance_units, NULL::integer AS scale, NULL::integer AS decimals
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                            LEFT JOIN economic_assets ea ON ea.id = a.asset_id
                           WHERE o.id = $1 AND a.status = 'ACTIVE' ORDER BY a.asset_id, a.account_type`, [viewer.house_id]),
        repository.query(`SELECT d.* FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id
                           WHERE o.id = $1 ORDER BY d.id DESC`, [viewer.house_id]),
        repository.query(`SELECT t.id, t.game_day, t.game_minute, t.transaction_kind, t.correlation_id,
                                 e.asset_id, e.delta_units
                            FROM economic_transactions t JOIN economic_entries e ON e.transaction_id = t.id
                           WHERE e.account_id IN (SELECT a.id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1)
                           ORDER BY t.id DESC LIMIT 100`, [viewer.house_id]),
        getTaxStatement(repository, viewer.id),
      ]);
      const projection = await getHouseFinancialProjection(repository, viewer.house_id);
      const canonicalRules = Object.entries(taxStatement.constitutionalTaxRules ?? {})
        .map(([code, value]) => ({
          code,
          value,
          versionId: taxStatement.constitutionalTaxVersionIds?.[code] ?? null,
          provenance: taxStatement.constitutionalTaxProvenance?.[code] ?? null,
        }));
      return {
        accounts: accounts.rows,
        summary: projection,
        deposits: deposits.rows,
        transactions: entries.rows,
        taxes: {
          rules: canonicalRules,
          obligations: taxStatement.taxObligations,
          generatedFrom: 'postgres-constitutional-tax-v5',
          constitutionSnapshotId: taxStatement.constitutionSnapshotId,
        },
      };
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
  if (url.pathname === '/api/finance/bank/risk' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getBankRiskProjection(repository));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  if (url.pathname.startsWith('/api/finance/institutions/') && request.method === 'GET') {
    const institutionId = url.pathname.split('/').pop() ?? '';
    const result = await withRepository(env, async (repository) => {
      const [accounts, state, obligations, financialProjection] = await Promise.all([
        repository.query(`SELECT a.id AS account_id, ea.code AS asset_code, a.asset_id, a.account_type, a.balance_units::TEXT AS balance_units
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id LEFT JOIN economic_assets ea ON ea.id = a.asset_id
                           WHERE o.id = $1 AND o.owner_type IN ('EARTH', 'CORPORATION', 'BANK')
                             AND a.asset_id = 1 AND a.account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND a.status = 'ACTIVE'
                           ORDER BY a.account_type`, [institutionId]),
        repository.query('SELECT * FROM financial_states WHERE institution_id = $1', [institutionId]),
        repository.query(`SELECT f.* FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id WHERE o.id = $1`, [institutionId]),
        getInstitutionFinancialProjection(repository, institutionId),
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
  if (url.pathname === '/api/finance/bank/loans' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listBankLoans(repository, viewer.id));
    return Response.json({ ...(result ?? { loans: [] }), persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/finance/bank/deposit-quote' && request.method === 'GET') {
    const amount = url.searchParams.get('amount')?.trim() ?? '';
    const termDays = Number(url.searchParams.get('termDays') ?? 30);
    if (!amount || !Number.isInteger(termDays) || termDays <= 0) return Response.json({ ok: false, error: 'decimal amount and positive termDays are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => getBankDepositQuote(repository, { amount, termDays }));
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Deposit quote unavailable' }, { status: 400 }); }
  }
  if (url.pathname === '/api/finance/bank/loan-quote' && request.method === 'GET') {
    const amount = url.searchParams.get('amount')?.trim() ?? '';
    const termDays = Number(url.searchParams.get('termDays') ?? 30);
    if (!amount || !Number.isInteger(termDays) || termDays <= 0) return Response.json({ ok: false, error: 'decimal amount and positive termDays are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => getBankLoanQuote(repository, { humanId: viewer.id, requestedUnits: parseCreditAmount(amount), termDays }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Loan quote unavailable' }, { status: 400 }); }
  }
  if (url.pathname === '/api/finance/bank/loan' && request.method === 'POST') {
    if (!featureEnabled(env, 'bankLoans')) return featureDisabledResponse('bankLoans');
    const parsed = await parseJsonBody<{ amount?: string; termDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const amount = parsed.value.amount?.trim() ?? '';
    const termDays = Number(parsed.value.termDays ?? 30);
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!amount || !Number.isInteger(termDays) || termDays <= 0 || !correlationId) return Response.json({ ok: false, error: 'decimal amount, positive termDays, and correlation ID are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => originateBankLoan(repository, { humanId: viewer.id, requestedUnits: parseCreditAmount(amount), termDays, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Loan origination failed' }, { status: 409 });
    }
  }
  const bankLoanRepayMatch = url.pathname.match(/^\/api\/finance\/bank\/loan\/([^/]+)\/repay$/);
  if (bankLoanRepayMatch && request.method === 'POST') {
    if (!featureEnabled(env, 'bankLoans')) return featureDisabledResponse('bankLoans');
    const parsed = await parseJsonBody<{ amount?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Correlation ID is required' }, { status: 400 });
    try {
      const amount = parsed.value.amount?.trim();
      const amountUnits = amount === undefined ? undefined : parseCreditAmount(amount);
      const result = await withRepository(env, (repository) => repayBankLoan(repository, { humanId: viewer.id, loanId: bankLoanRepayMatch[1], amountUnits, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Loan repayment failed' }, { status: 409 });
    }
  }
  const bankLoanGuaranteeMatch = url.pathname.match(/^\/api\/finance\/bank\/loan\/([^/]+)\/guarantee$/);
  if (bankLoanGuaranteeMatch && request.method === 'POST') {
    if (!featureEnabled(env, 'bankLoans')) return featureDisabledResponse('bankLoans');
    const parsed = await parseJsonBody<{ guaranteedUnits?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const guaranteedUnits = parsed.value.guaranteedUnits?.trim() ?? '';
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!/^\d+$/.test(guaranteedUnits) || !correlationId) return Response.json({ ok: false, error: 'guaranteedUnits and correlation ID are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => addBankLoanGuarantee(repository, { humanId: viewer.id, loanId: bankLoanGuaranteeMatch[1], guaranteedUnits: BigInt(guaranteedUnits), correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Loan guarantee failed' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/finance/bank/deposit' && request.method === 'POST') {
    if (!featureEnabled(env, 'bankDeposits')) return featureDisabledResponse('bankDeposits');
    const parsed = await parseJsonBody<{ amount?: string; termDays?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Correlation ID is required' }, { status: 400 });
    try {
      const amount = parsed.value.amount?.trim() ?? '';
      if (!amount) return Response.json({ ok: false, error: 'decimal amount is required' }, { status: 400 });
      const result = await withRepository(env, (repository) => createBankDeposit(repository, { humanId: viewer.id, amount, termDays: Number(parsed.value.termDays ?? 7), correlationId }));
      return Response.json({ ...(result ?? { ok: false }), persistence: 'planetscale-postgres' }, { status: result?.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Bank deposit failed' }, { status: 409 });
    }
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
    } catch (error) {
      if (isSettlementBarrierError(error)) return error.toResponse();
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Bank withdrawal failed' }, { status: 409 });
    }
  }
  if (url.pathname === '/api/finance/personal' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, state, buildings, context, latestMaintenance, arrears, taxObligations, bankDeposits, transactions, v5Capacity, v5Obligations, canonicalTaxStatement] = await Promise.all([
        repository.query(`SELECT a.id::TEXT AS account_id, a.balance_units::TEXT AS balance_units,
                                 'CREDIT' AS currency,
                                 a.account_type
                            FROM economic_accounts a
                            JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                           WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [viewer.house_id]),
        repository.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [viewer.id]),
        repository.query("SELECT b.id, b.catalog_id, b.status FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id JOIN building_catalog c ON c.id = b.catalog_id WHERE o.id = $1 AND c.ownership_scope = 'PRIVATE'", [viewer.house_id]),
        repository.query<{ age_years: number; corporation_id: string | null; living_cost_index: string }>("SELECT h.age_years, ha.corporation_id, w.living_cost_index FROM humans h LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE' CROSS JOIN world_state w WHERE h.id = $1 AND w.id = 'WORLD'", [viewer.id]),
        repository.query('SELECT game_day, food_required_units, food_consumed_units, food_shortfall_units, shortfall_notes, status FROM personal_life_maintenance WHERE human_id = $1 ORDER BY game_day DESC LIMIT 1', [viewer.id]),
        repository.query<{ total: string }>('SELECT COALESCE(SUM(food_shortfall_units), 0) AS total FROM personal_life_maintenance WHERE human_id = $1', [viewer.id]),
        repository.query('SELECT t.id, t.tax_type, t.tax_base_units, t.rate_bps, t.amount_units, t.rule_version, t.game_day, t.status, t.due_game_day FROM tax_obligations t JOIN owner_registry o ON o.economic_id = t.taxpayer_economic_id WHERE o.id = $1 ORDER BY t.game_day DESC, t.id DESC', [viewer.house_id]),
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
        getV5HouseCapacity(repository, viewer.house_id).catch(() => null),
        repository.query(`SELECT o.id, o.game_day, o.usage_units::TEXT, o.assessed_units::TEXT, o.paid_units::TEXT,
                                 o.status, o.schedule_id, o.financial_obligation_id
                            FROM v5_capacity_obligations o
                           WHERE o.house_id = $1 ORDER BY o.game_day DESC, o.created_at DESC LIMIT 100`, [viewer.house_id]).catch(() => ({ rows: [] })),
        getTaxStatement(repository, viewer.id).catch(() => null),
      ]);
      const walletUnits = BigInt(account.rows[0]?.balance_units ?? 0);
      return {
        account: account.rows[0] ?? null,
        taxes: {
          rules: canonicalTaxStatement?.activeRules ?? [],
          constitutionalRules: canonicalTaxStatement?.constitutionalTaxRules ?? {},
          constitutionalVersionIds: canonicalTaxStatement?.constitutionalTaxVersionIds ?? {},
          obligations: taxObligations.rows,
          generatedFrom: canonicalTaxStatement ? 'postgres-constitutional-tax-v5' : 'unavailable-canonical-tax-statement',
        },
        capacity: { summary: v5Capacity, obligations: v5Obligations.rows },
        liquidity: {
          walletUnits: walletUnits.toString(),
          availableToSpendUnits: walletUnits.toString(),
          nextSettlementGameDay: (await readAuthoritativeGameTime(repository)).gameDay + 1,
          generatedFrom: 'postgres-canonical-facts-v5',
        },
        bank: { deposits: bankDeposits.rows },
        transactions: transactions.rows,
      };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [account, canonicalTaxStatement] = await Promise.all([
        repository.query(`SELECT a.id::TEXT AS account_id, o.id AS owner_id, a.balance_units::TEXT AS balance_units, 'CREDIT' AS currency
                            FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
                           WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [viewer.house_id]),
        getTaxStatement(repository, viewer.id).catch(() => null),
      ]);
      return {
        account: account.rows[0] ?? null,
        taxRules: canonicalTaxStatement?.activeRules ?? [],
        constitutionalRules: canonicalTaxStatement?.constitutionalTaxRules ?? {},
        constitutionalVersionIds: canonicalTaxStatement?.constitutionalTaxVersionIds ?? {},
        progressiveSchedules: canonicalTaxStatement?.progressiveSchedules ?? {},
        generatedFrom: canonicalTaxStatement
          ? 'postgres-constitutional-tax-v5'
          : 'unavailable-canonical-tax-statement',
      };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/finance/liquidity' && request.method === 'GET') {
    const liquidity = (await withRepository(env, (repository) =>
      repository.query<{ active_humans: number; money_supply: string; living_cost_index: string }>(
        "SELECT (SELECT COUNT(*) FROM humans WHERE status = 'ACTIVE') AS active_humans, (SELECT COALESCE(SUM(a.balance_units), 0) FROM economic_accounts a WHERE a.asset_id = 1 AND a.account_type IN ('WALLET', 'TREASURY', 'OPERATIONS', 'RESERVE') AND a.status = 'ACTIVE') AS money_supply, 1::NUMERIC AS living_cost_index",
      ),
    ))?.rows[0];
    const activeHumans = Number(liquidity?.active_humans ?? 0);
    const supply = BigInt(String(liquidity?.money_supply ?? '0'));
    const target = BigInt(activeHumans) * 100n;
    const low = target * 80n / 100n;
    const high = target * 120n / 100n;
    return Response.json({
      activeHumans,
      moneySupplyUnits: supply.toString(),
      targetUnits: target.toString(),
      corridor: { lowUnits: low.toString(), highUnits: high.toString() },
      status: supply < low ? 'below-corridor' : supply > high ? 'above-corridor' : 'inside-corridor',
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
  const organizationRiskMatch = url.pathname.match(/^\/api\/finance\/organizations\/([^/]+)\/risk$/);
  if (organizationRiskMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getOrganizationFinancialState(repository, organizationRiskMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ok: true, ...result, persistence: 'planetscale-postgres' });
  }
  const organizationResolutionMatch = url.pathname.match(/^\/api\/finance\/organizations\/([^/]+)\/resolution$/);
  if (organizationResolutionMatch && request.method === 'POST') {
    const parsed = await parseJsonBody<{ caseType?: 'RESTRUCTURE' | 'MERGER' | 'SPLIT' | 'DISSOLUTION'; successorOrganizationId?: string; proposalId?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);
    if (!correlationId || !parsed.value.caseType || !parsed.value.proposalId) return Response.json({ ok: false, error: 'caseType, proposalId, and correlation ID are required' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => createOrganizationResolutionCase(repository, { organizationId: organizationResolutionMatch[1], caseType: parsed.value.caseType!, successorOrganizationId: parsed.value.successorOrganizationId, proposalId: parsed.value.proposalId!, humanId: viewer.id, correlationId }));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) { return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Resolution case creation failed' }, { status: 409 }); }
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

  const corporationFiscalMatch = url.pathname.match(/^\/api\/finance\/corporations\/([^/]+)$/);
  if (corporationFiscalMatch && request.method === 'GET') {
    const result = await withRepository(env, (repository) => getCorporationFiscalState(repository, corporationFiscalMatch[1]));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  return null;
}
