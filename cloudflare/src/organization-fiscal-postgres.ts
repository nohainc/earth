import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';

async function day(tx: PostgresRepository): Promise<number> {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

async function authorized(tx: PostgresRepository, organizationId: string, houseId: string, capability: string): Promise<void> {
  const result = await tx.query(`SELECT 1 FROM organization_memberships m JOIN organization_charter_versions v ON v.organization_id = m.organization_id AND v.effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD')) WHERE m.organization_id = $1 AND m.house_id = $2 AND m.status = 'ACTIVE' AND m.role_code IN ('FOUNDER','ADMIN','TREASURER','GOVERNOR') AND (v.charter->'capabilities') ? $3`, [organizationId, houseId, capability]);
  if (!result.rows[0]) throw new Error(`Organization ${capability.toLowerCase()} capability denied`);
}

export async function provisionOrganizationEconomy(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const organization = (await tx.query<{ id: string; archetype: string }>("SELECT id, archetype FROM organizations WHERE id = $1 AND status = 'ACTIVE'", [organizationId])).rows[0];
    if (!organization) throw new Error('Organization not found');
    const capable = await tx.query("SELECT 1 FROM organization_charter_versions WHERE organization_id = $1 AND effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD')) AND (charter->'capabilities') ? 'ECONOMIC_OWNER' AND (charter->'authorityLimits'->>'canOwnAssets')::BOOLEAN = TRUE", [organizationId]);
    if (!capable.rows[0]) throw new Error('Organization is not eligible for an economy');
    const existing = (await tx.query<{ economic_id: string }>('SELECT economic_id FROM organization_economies WHERE organization_id = $1', [organizationId])).rows[0];
    const economicId = existing?.economic_id ?? `ECON-ORG-${organizationId}`;
    const provisionedDay = await day(tx);
    await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'ORGANIZATION', $2) ON CONFLICT (id) DO NOTHING`, [organizationId, economicId]);
    await tx.query(`INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance_units, status) SELECT $1, 1, code, 0, 'ACTIVE' FROM economic_account_types WHERE code IN ('TREASURY','OPERATIONS','RESERVE') ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING`, [economicId]);
    await tx.query(`INSERT INTO organization_economies (organization_id, economic_id, provisioned_game_day, rules_version) VALUES ($1,$2,$3,'organization-economy-v1') ON CONFLICT (organization_id) DO NOTHING`, [organizationId, economicId, provisionedDay]);
    return { ok: true, organizationId, economicId, archetype: organization.archetype, accounts: (await tx.query(`SELECT account_type, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND status = 'ACTIVE' ORDER BY account_type`, [economicId])).rows };
  });
}

export async function getOrganizationFinance(repository: PostgresRepository, organizationId: string, houseId: string): Promise<Record<string, unknown>> {
  const access = await repository.query(`SELECT 1 FROM organization_memberships WHERE organization_id = $1 AND house_id = $2 AND status = 'ACTIVE'`, [organizationId, houseId]);
  if (!access.rows[0]) throw new Error('Organization membership required');
  const economy = (await repository.query<{ economic_id: string }>('SELECT economic_id FROM organization_economies WHERE organization_id = $1', [organizationId])).rows[0];
  if (!economy) return { organizationId, provisioned: false, budgets: [], accounts: [] };
  const [accounts, budgets, obligations] = await Promise.all([
    repository.query(`SELECT account_type, balance_units::TEXT AS balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND status = 'ACTIVE' ORDER BY account_type`, [economy.economic_id]),
    repository.query('SELECT * FROM organization_budget_lines WHERE organization_id = $1 AND status = \'ACTIVE\' ORDER BY category_code', [organizationId]),
    repository.query(`SELECT * FROM financial_obligations WHERE debtor_economic_id = $1 AND status IN ('DUE','PARTIAL','ARREARS') ORDER BY due_game_day, priority_class`, [economy.economic_id]),
  ]);
  return { organizationId, provisioned: true, economicId: economy.economic_id, accounts: accounts.rows, budgets: budgets.rows, obligations: obligations.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function spendOrganizationBudget(repository: PostgresRepository, input: { organizationId: string; houseId: string; budgetLineId: string; sourceAccountType: 'TREASURY' | 'OPERATIONS'; destinationAccountId: string; amountUnits: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const actor = (await tx.query<{ human_id: string }>('SELECT h.current_human_id AS human_id FROM houses h WHERE h.id = $1 AND h.status = \'ACTIVE\'', [input.houseId])).rows[0];
    if (!actor?.human_id) throw new Error('Active Human authority is required');
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: actor.human_id, action: 'ECONOMIC_OWNER', amountUnits: BigInt(input.amountUnits) });
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n) throw new Error('Spend amount must be positive');
    const line = (await tx.query<{ organization_id: string; authorized_units: string; committed_units: string; spent_units: string }>('SELECT organization_id, authorized_units::TEXT, committed_units::TEXT, spent_units::TEXT FROM organization_budget_lines WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE', [input.budgetLineId])).rows[0];
    if (!line || line.organization_id !== input.organizationId) throw new Error('Budget line not found');
    if (BigInt(line.authorized_units) - BigInt(line.committed_units) - BigInt(line.spent_units) < amount) throw new Error('Budget authority exceeded');
    const account = (await tx.query<{ id: string; balance_units: string }>(`SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a JOIN organization_economies e ON e.economic_id = a.owner_economic_id WHERE e.organization_id = $1 AND a.asset_id = 1 AND a.account_type = $2 AND a.status = 'ACTIVE' FOR UPDATE`, [input.organizationId, input.sourceAccountType])).rows[0];
    if (!account || BigInt(account.balance_units) < amount) throw new Error('Organization cash balance is insufficient');
    const destination = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE id = $1 AND asset_id = 1 AND status = \'ACTIVE\' AND id <> $2', [input.destinationAccountId, account.id])).rows[0];
    if (!destination) throw new Error('Spend destination account is unavailable');
    const dayValue = await day(tx);
    const result = await tx.query(`SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,'ASSET_TRANSFER','ORGANIZATION',$3,'organization-spend-v1',$4::JSONB)`, [input.correlationId, dayValue, input.organizationId, JSON.stringify([{ account_id: account.id, asset_id: 1, delta_units: (-amount).toString() }, { account_id: destination.id, asset_id: 1, delta_units: amount.toString() }])]);
    if (!result.rows[0]?.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    await tx.query('UPDATE organization_budget_lines SET spent_units = spent_units + $1 WHERE id = $2', [amount.toString(), input.budgetLineId]);
    await createGameEvent(tx, { id: `ORG-SPEND-${input.correlationId}`, category: 'ORGANIZATION', eventType: 'ORGANIZATION_BUDGET_SPENT', gameDay: dayValue, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Organization budget spent', details: { budgetLineId: input.budgetLineId, amountUnits: amount.toString() }, correlationId: input.correlationId });
    return { ok: true, amountUnits: amount.toString(), budgetLineId: input.budgetLineId, correlationId: input.correlationId };
  });
}
