import type { PostgresRepository } from './repository.ts';
import { moneyToCents, centsToMoney } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';
import { createNotification } from './notifications-postgres.ts';

function budgetCategory(category: string): string {
  const normalized = category.trim().toUpperCase().replace(/[-\s]+/g, '_');
  return ({ PUBLIC_SERVICES: 'ESSENTIAL_SERVICES', MAINTENANCE: 'ESSENTIAL_SERVICES', ESSENTIAL_SERVICE: 'ESSENTIAL_SERVICES' } as Record<string, string>)[normalized] ?? normalized;
}

export async function getCorporationFiscalState(repository: PostgresRepository, corporationId: string): Promise<Record<string, unknown>> {
  const [corporation, accounts, budgets, taxes] = await Promise.all([
    repository.query('SELECT c.id, i.name, c.status, c.admission_policy FROM corporations c JOIN institutions i ON i.id = c.id WHERE c.id = $1', [corporationId]),
    repository.query(`SELECT a.id::TEXT AS account_id, a.account_type, a.balance_units::TEXT AS balance_units
      FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE o.id = $1 AND o.owner_type = 'CORPORATION' AND a.asset_id = 1 AND a.status = 'ACTIVE'
      ORDER BY a.account_type`, [corporationId]),
    repository.query(`SELECT l.*, bc.category_code, bc.spending_class, bc.priority
      FROM institution_budget_lines l JOIN budget_categories bc ON bc.id = l.category_id
      WHERE l.institution_id = $1 ORDER BY bc.priority, bc.category_code`, [corporationId]),
    repository.query(`SELECT r.* FROM tax_rule_versions r
      WHERE r.scope = 'CORPORATION' AND r.beneficiary_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1)
      ORDER BY r.category, r.effective_from_game_day DESC`, [corporationId]),
  ]);
  if (!corporation.rows[0]) throw new Error('Corporation not found');
  return { corporation: corporation.rows[0], accounts: accounts.rows, budgets: budgets.rows, taxRules: taxes.rows, fiscalLayers: ['EARTH', 'CORPORATION'] };
}

export async function spendCorporationBudget(
  repository: PostgresRepository,
  input: { actorId: string; corporationId: string; category: string; amount: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const authority = await tx.query(`SELECT 1 FROM institution_governance_roles
      WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
        AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`, [input.corporationId, input.actorId]);
    if (!authority.rows[0]) throw new Error('Corporation spending permission is required');
    const amountUnits = moneyToCents(input.amount);
    if (amountUnits <= 0n) throw new Error('Public spending amount must be positive');
    const world = (await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'")).rows[0];
    const gameDay = Number(world?.game_day ?? 1);
    const prior = await tx.query<{ source_id: string; game_day: number }>('SELECT source_id, game_day FROM economic_transactions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, corporationId: input.corporationId, gameDay: prior.rows[0].game_day, correlationId: input.correlationId };
    const budget = (await tx.query<{ id: string; authorized_units: string; committed_units: string; spent_units: string }>(
      `SELECT l.id, l.authorized_units, l.committed_units, l.spent_units
         FROM institution_budget_lines l JOIN budget_categories c ON c.id = l.category_id
        WHERE l.institution_id = $1 AND c.institution_kind = 'CORPORATION' AND c.category_code = $2
          AND l.fiscal_period_id = (SELECT id FROM fiscal_periods WHERE start_game_day <= $3 AND end_game_day >= $3 AND status = 'ACTIVE' LIMIT 1)
        FOR UPDATE`, [input.corporationId, budgetCategory(input.category), gameDay],
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
    const transaction = (await tx.query<{ id: string }>(
      `SELECT earth_post_transaction($1, $2, $3, 'CORPORATION_PUBLIC_SPENDING', 'CORPORATION', $4, 'corporation-fiscal-v1', $5::JSONB) AS id`,
      [input.correlationId, gameDay, Number(world?.game_minute ?? 0), input.corporationId, JSON.stringify([
        { account_id: treasury.account_id, delta_units: (-amountUnits).toString(), asset_id: 1 },
        { account_id: operations.account_id, delta_units: amountUnits.toString(), asset_id: 1 },
      ])],
    )).rows[0];
    await tx.query('UPDATE institution_budget_lines SET spent_units = spent_units + $1 WHERE id = $2', [amountUnits.toString(), budget.id]);
    await tx.query(`INSERT INTO institution_financial_events
      (institution_id, game_day, event_type, amount_units, budget_line_id, economic_transaction_id, correlation_id)
      VALUES ($1, $2, 'CORPORATION_PUBLIC_SPENDING', $3, $4, $5, $6)`, [input.corporationId, gameDay, amountUnits.toString(), budget.id, transaction.id, input.correlationId]);
    await createNotification(tx, { id: crypto.randomUUID(), humanId: input.actorId, notificationType: 'finance', title: 'Corporation public spending recorded', body: `${Number(centsToMoney(amountUnits))} Credits were allocated to Corporation public operations.`, entityType: 'corporation', entityId: input.corporationId, gameDay, correlationId: `${input.correlationId}:notification` });
    return { ok: true, amount: Number(centsToMoney(amountUnits)), corporationId: input.corporationId, category: input.category, gameDay, transactionId: transaction.id, correlationId: input.correlationId };
  });
}
