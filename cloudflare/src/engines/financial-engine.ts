import type { PostgresRepository } from '../repository.ts';
import { centsToMoney, moneyToCents } from '../money.ts';
import { transferCredits } from '../financial-postgres.ts';

export interface FinancialSettlementResult {
  depreciationCount: number;
  taxesCollected: string;
  supplyContractsSettled: number;
  entitiesEvaluated: number;
}

export async function settleContinuousFinancials(
  repo: PostgresRepository,
  elapsedDays: number,
  gameDay: number,
): Promise<FinancialSettlementResult> {
  if (elapsedDays <= 0) return { depreciationCount: 0, taxesCollected: '0', supplyContractsSettled: 0, entitiesEvaluated: 0 };

  let depreciationCount = 0;
  let taxesCollectedCents = 0n;
  let supplyContractsSettled = 0;

// Machine depreciation logic removed; machines are now handled via buildings.

  // 2. Settle continuous supply contracts
  const activeContracts = await repo.query<{
    contract_id: string;
    resource_type: string;
    daily_quantity: string;
    unit_price: string;
    buyer_id: string;
    seller_id: string;
  }>(
    `SELECT sc.contract_id, sc.resource_type, sc.daily_quantity, sc.unit_price, ev.buyer_id, ev.seller_id
     FROM supply_contracts sc
     JOIN negotiated_contracts nc ON nc.id = sc.contract_id
     JOIN contract_escrow_vaults ev ON ev.contract_id = sc.contract_id
     WHERE nc.status = 'accepted' FOR UPDATE OF sc`,
  );

  for (const c of activeContracts.rows) {
    const qty = Math.round(Number(c.daily_quantity ?? 0) * elapsedDays * 100) / 100;
    const credits = Math.round(qty * Number(c.unit_price ?? 0) * 100) / 100;
    if (qty <= 0 || credits <= 0) continue;

    // Transfer resource from seller to buyer
    await repo.query(
      'UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1',
      [qty, c.seller_id, c.resource_type],
    );
    await repo.query(
      'INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount',
      [c.buyer_id, c.resource_type, qty],
    );

    // Transfer credits from buyer to seller
    await repo.query(
      "UPDATE account_balances SET balance = balance - $1 WHERE owner_id = $2 AND currency = 'CREDIT'",
      [credits, c.buyer_id],
    );
    await repo.query(
      "UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2 AND currency = 'CREDIT'",
      [credits, c.seller_id],
    );

    supplyContractsSettled += 1;
  }

  // 3. Evaluate solvency status across all businesses
  const businesses = await repo.query<{ id: string; owner_id: string; condition: string }>(
    "SELECT id, owner_id, condition FROM businesses WHERE status = 'active'",
  );
  for (const b of businesses.rows) {
    const balance = (await repo.query<{ balance: string }>(
      "SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
      [b.owner_id],
    )).rows[0]?.balance ?? '0';

    const financials = (await repo.query<{ profit: string }>(
      'SELECT profit FROM business_financials WHERE business_id = $1',
      [b.id],
    )).rows[0];

    const profit = Number(financials?.profit ?? 0);
    const cond = Number(b.condition ?? 100);

    let status = 'active';
    if (profit < -10000 || cond < 10) status = 'insolvent';
    else if (profit < 0 || cond < 30) status = 'distressed';

    await repo.query('UPDATE businesses SET status = $1 WHERE id = $2', [status, b.id]);
  }

  return {
    depreciationCount,
    taxesCollected: centsToMoney(taxesCollectedCents),
    supplyContractsSettled,
    entitiesEvaluated: businesses.rows.length,
  };
}
