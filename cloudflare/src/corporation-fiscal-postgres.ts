import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { moneyToCents, centsToMoney } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';
import { createNotification } from './notifications-postgres.ts';
import { getActiveV5StandardCapacity, getV5CorporationCapacity } from './v5-capacity-postgres.ts';
import { runEconomicMutation, postEconomicTransaction } from './settlement-barrier-postgres.ts';

function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)])) as T;
  }
  return value;
}

function budgetCategory(category: string): string {
  const normalized = category.trim().toUpperCase().replace(/[-\s]+/g, '_');
  return ({ PUBLIC_SERVICES: 'ESSENTIAL_SERVICES', MAINTENANCE: 'ESSENTIAL_SERVICES', ESSENTIAL_SERVICE: 'ESSENTIAL_SERVICES' } as Record<string, string>)[normalized] ?? normalized;
}

export async function getCorporationFiscalState(repository: PostgresRepository, corporationId: string): Promise<Record<string, unknown>> {
  const [corporation, accounts, budgets, constitution, v5Capacity] = await Promise.all([
    // V5 fiscal reads must not expose the retired tax-charter authority. Tax
    // policy from tax_rule_versions is read from the resolved Constitution snapshot below; returning
    // the legacy columns would invite clients to choose the wrong source.
    repository.query('SELECT c.id, i.name, c.status, c.admission_policy FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1', [corporationId]),
    repository.query(`SELECT a.id::TEXT AS account_id, a.asset_id, ea.code AS asset_code, ea.code AS asset_name,
             ea.asset_kind, a.account_type, a.balance_units::TEXT AS balance_units
      FROM economic_accounts a
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      JOIN economic_assets ea ON ea.id = a.asset_id
      WHERE o.id = $1 AND o.owner_type = 'CORPORATION' AND a.status = 'ACTIVE'
      ORDER BY a.asset_id, a.account_type`, [corporationId]),
    repository.query(`SELECT l.*, bc.category_code, bc.spending_class, bc.priority
      FROM institution_budget_lines l JOIN budget_categories bc ON bc.id = l.category_id
      WHERE l.institution_id = $1 ORDER BY bc.priority, bc.category_code`, [corporationId]),
    repository.query(`SELECT rules_json, version_ids, game_day
        FROM resolved_constitution_snapshots_v5
       WHERE authority_type = 'CORPORATION' AND authority_id = $1
         AND game_day = (SELECT game_day FROM earth_get_current_game_time())`, [corporationId]),
    getActiveV5StandardCapacity(repository)
      .then((policy) => getV5CorporationCapacity(repository, corporationId, policy.standardTerritoryCapacity))
      .catch(() => null),
  ]);
  if (!corporation.rows[0]) throw new Error('Corporation not found');
  const canonical = constitution.rows[0] ?? null;
  const constitutionalTaxRules = canonical ? Object.fromEntries(Object.entries(canonical.rules_json ?? {}).filter(([code]) => code.includes('.TAX') || code === 'CORPORATION.HOUSE_INCOME_TAX')) : {};
  const constitutionalTaxVersionIds = canonical ? Object.fromEntries(Object.entries(canonical.version_ids ?? {}).filter(([code]) => code.includes('.TAX') || code === 'CORPORATION.HOUSE_INCOME_TAX')) : {};
  
  const resourceBalances: Record<string, string> = {
    energy: '0',
    food: '0',
    material: '0',
    components: '0',
    compute: '0',
  };
  const creditBalances: Record<string, string> = {
    treasury: '0',
    operations: '0',
    reserve: '0',
  };

  for (const acct of accounts.rows as Array<{ asset_code: string; account_type: string; balance_units: string }>) {
    const key = acct.asset_code.toLowerCase();
    if (acct.account_type === 'INVENTORY' && key in resourceBalances) {
      resourceBalances[key] = acct.balance_units;
    }
    if (acct.asset_code === 'CREDIT') {
      const typeKey = acct.account_type.toLowerCase();
      if (typeKey in creditBalances) {
        creditBalances[typeKey] = acct.balance_units;
      }
    }
  }

  return {
    corporation: corporation.rows[0],
    accounts: accounts.rows,
    resourceBalances,
    creditBalances,
    budgets: budgets.rows,
    constitutionalTaxRules,
    constitutionalTaxVersionIds,
    taxRules: [],
    taxRulesSource: canonical ? 'constitution-snapshot-v5' : 'unavailable-canonical-snapshot',
    canonicalTaxSnapshotAvailable: Boolean(canonical),
    capacity: toJsonSafe(v5Capacity),
    capacitySource: v5Capacity ? 'postgres-v5-structural-settlement-profile' : 'unavailable-canonical-capacity-read-model',
    fiscalLayers: ['EARTH', 'CORPORATION'],
  };
}

export async function spendCorporationBudget(
  repository: PostgresRepository,
  input: { actorId: string; corporationId: string; category: string; amount: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const authority = await tx.query(`SELECT 1 FROM institution_governance_roles
      WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
        AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`, [input.corporationId, input.actorId]);
    if (!authority.rows[0]) throw new Error('Corporation spending permission is required');
    const amountUnits = moneyToCents(input.amount);
    if (amountUnits <= 0n) throw new Error('Public spending amount must be positive');
    const gameDay = clock.gameDay;
    const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1`, [input.corporationId])).rows[0]?.status;
    const spendingCategory = budgetCategory(input.category);
    if (delinquency === 'EARTH_RECEIVERSHIP' && spendingCategory !== 'ESSENTIAL_SERVICES') throw new Error('Corporation receivership blocks discretionary spending');
    if (delinquency === 'EXPANSION_SPENDING_RESTRICTED' && !['ESSENTIAL_SERVICES', 'MAINTENANCE'].includes(spendingCategory)) throw new Error('Corporation capacity delinquency blocks discretionary spending');
    const prior = await tx.query<{ source_id: string; game_day: number }>('SELECT source_id, game_day FROM economic_transactions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, corporationId: input.corporationId, gameDay: prior.rows[0].game_day, correlationId: input.correlationId };
    const budget = (await tx.query<{ id: string; authorized_units: string; committed_units: string; spent_units: string }>(
      `SELECT l.id, l.authorized_units, l.committed_units, l.spent_units
         FROM institution_budget_lines l JOIN budget_categories c ON c.id = l.category_id
        WHERE l.institution_id = $1 AND c.institution_kind = 'CORPORATION' AND c.category_code = $2
          AND l.fiscal_period_id = (SELECT id FROM fiscal_periods WHERE start_game_day <= $3 AND end_game_day >= $3 AND status = 'ACTIVE' LIMIT 1)
        FOR UPDATE`, [input.corporationId, spendingCategory, gameDay],
    )).rows[0];
    if (!budget) throw new Error('Corporation budget line is unavailable');
    if (BigInt(budget.authorized_units) - BigInt(budget.committed_units) - BigInt(budget.spent_units) < amountUnits) throw new Error('Spending exceeds the Corporation budget');
    const accounts = (await tx.query<{ account_type: string; account_id: string; balance_units: string }>(
      `SELECT a.account_type, a.id::TEXT AS account_id, a.balance_units::TEXT
         FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.id = $1 AND o.owner_type = 'CORPORATION' AND a.asset_id = 1
          AND a.account_type IN ('TREASURY', 'OPERATIONS') AND a.status = 'ACTIVE' FOR UPDATE`, [input.corporationId],
    )).rows;
    const treasury = accounts.find((account) => account.account_type === 'TREASURY');
    const operations = accounts.find((account) => account.account_type === 'OPERATIONS');
    if (!treasury || !operations) throw new Error('Corporation treasury or operations account is unavailable');
    if (BigInt(treasury.balance_units) < amountUnits) throw new Error('Corporation treasury cannot fund this spending');
    const transaction = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'ASSET_TRANSFER',
      sourceType: 'CORPORATION_INTERNAL',
      sourceId: input.corporationId,
      rulesVersion: 'corporation-fiscal-v2',
      entries: [
        { account_id: treasury.account_id, delta_units: (-amountUnits).toString(), asset_id: 1 },
        { account_id: operations.account_id, delta_units: amountUnits.toString(), asset_id: 1 },
      ],
    }, clock);
    // Treasury -> Operations is an internal allocation. It reserves no budget
    // authority and is not external spending; external settlement uses the
    // institution-spending service and is the only path that increments spent_units.
    return { ok: true, amount: Number(centsToMoney(amountUnits)), corporationId: input.corporationId, category: input.category, gameDay, transactionId: transaction.transactionId, internalAllocation: true, committed: budget.committed_units, spent: budget.spent_units, correlationId: input.correlationId };
  });
}
