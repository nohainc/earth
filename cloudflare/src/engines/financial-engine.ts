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
  const buildings = await repo.query<{ id: string; owner_id: string; condition: string }>(
    "SELECT id, owner_id, condition FROM buildings WHERE status = 'active' AND ownership_class = 'private'",
  );
  const owners = new Map<string, { condition: number }>();
  for (const building of buildings.rows) {
    owners.set(building.owner_id, { condition: Math.min(owners.get(building.owner_id)?.condition ?? 100, Number(building.condition ?? 100)) });
  }
  for (const [ownerId, owner] of owners) {
    const balance = (await repo.query<{ balance: string }>(
      "SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
      [ownerId],
    )).rows[0]?.balance ?? '0';
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
