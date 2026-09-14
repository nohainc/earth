import type { PostgresRepository } from '../repository.ts';
import { centsToMoney, moneyToCents } from '../money.ts';
import { transferCredits } from '../financial-postgres.ts';

export interface FinancialSettlementResult {
  depreciationCount: number;
  taxesCollected: string;
  entitiesEvaluated: number;
}

export async function settleContinuousFinancials(
  repo: PostgresRepository,
  elapsedDays: number,
  gameDay: number,
): Promise<FinancialSettlementResult> {
  if (elapsedDays <= 0) return { depreciationCount: 0, taxesCollected: '0', entitiesEvaluated: 0 };

  let depreciationCount = 0;
  let taxesCollectedCents = 0n;

// Machine depreciation logic removed; machines are now handled via buildings.

  // 2. Evaluate solvency across Human-owned private operations.
  const buildings = await repo.query<{ id: string; owner_id: string }>(
    "SELECT id, owner_id FROM buildings WHERE status = 'active' AND ownership_class = 'private'",
  );
  const owners = new Map<string, { condition: number }>();
  for (const building of buildings.rows) {
    owners.set(building.owner_id, { condition: 100 });
  }
  for (const [ownerId, owner] of owners) {
    const balance = (await repo.query<{ balance_units: string }>(
      "SELECT COALESCE(a.balance_units, 0)::TEXT AS balance_units FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'",
      [ownerId],
    )).rows[0]?.balance_units ?? '0';
    if (Number(balance) < 0 || owner.condition < 10) {
      await repo.query("UPDATE buildings SET status = 'inactive' WHERE owner_id = $1 AND ownership_class = 'private' AND status = 'active'", [ownerId]);
    }
  }

  return {
    depreciationCount,
    taxesCollected: centsToMoney(taxesCollectedCents),
    entitiesEvaluated: owners.size,
  };
}
