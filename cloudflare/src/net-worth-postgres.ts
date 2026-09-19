import type { PostgresRepository } from './repository.ts';

export const HOUSE_NET_WORTH_VALUATION_POLICY = {
  code: 'HOUSE_NET_WORTH_V5_COST_BASIS_MARKET_INVENTORY',
  description: 'Wallet and deposits use ledger balances; commodities use the latest completed market price; Buildings/Productive Assets use catalog construction cost; outstanding debt is deducted. Corporation equity is excluded.',
  buildings: 'catalog construction cost in CREDIT units',
  commodities: 'latest completed market price in CREDIT units',
  deposits: 'principal balance in CREDIT units',
  debt: 'outstanding principal plus accrued interest in CREDIT units',
};

export interface HouseNetWorthSnapshot {
  id: string;
  house_id: string;
  current_human_id: string | null;
  game_day: number;
  liquid_credits_units: string;
  deposit_principal_units: string;
  commodity_valuation_units: string;
  buildings_valuation_units: string;
  debt_units: string;
  total_net_worth_units: string;
  valuation_policy: string;
  created_at: string;
}

export interface HouseNetWorthSummary {
  currentNetWorthUnits: string;
  liquidCreditsUnits: string;
  depositPrincipalUnits: string;
  commodityValuationUnits: string;
  buildingsValuationUnits: string;
  debtUnits: string;
  growthRatePct: number;
  peakNetWorthUnits: string;
  peakDay: number;
  assetAllocation: { cashPct: number; depositsPct: number; commoditiesPct: number; buildingsPct: number; debtPct: number };
}

function units(value: unknown): bigint { try { return BigInt(String(value ?? '0')); } catch { return 0n; } }
function pct(part: bigint, total: bigint): number { return total > 0n ? Number((part * 1000n) / total) / 10 : 0; }

export async function getNetWorthHistory(client: any, humanId: string) {
  const house = (await client.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1 AND status = \'ACTIVE\'', [humanId])).rows[0];
  const houseId = house?.house_id ?? null;
  const res = houseId == null ? { rows: [] } : await client.query(`SELECT id, house_id, current_human_id, game_day,
      liquid_credits_units::TEXT, deposit_principal_units::TEXT, commodity_valuation_units::TEXT,
      buildings_valuation_units::TEXT, debt_units::TEXT, total_net_worth_units::TEXT, valuation_policy, created_at
      FROM net_worth_snapshots WHERE house_id = $1 ORDER BY game_day ASC LIMIT 60`, [houseId]);
  const snapshots: HouseNetWorthSnapshot[] = res.rows;
  const latest = snapshots.at(-1);
  const first = snapshots[0];
  const current = units(latest?.total_net_worth_units);
  const initial = units(first?.total_net_worth_units);
  let peak = 0n; let peakDay = 1;
  for (const snapshot of snapshots) { const total = units(snapshot.total_net_worth_units); if (total > peak) { peak = total; peakDay = Number(snapshot.game_day); } }
  const cash = units(latest?.liquid_credits_units);
  const deposits = units(latest?.deposit_principal_units);
  const commodities = units(latest?.commodity_valuation_units);
  const buildings = units(latest?.buildings_valuation_units);
  const debt = units(latest?.debt_units);
  const base = current > 0n ? current : 1n;
  return {
    ok: true, houseId, currentHumanId: humanId, valuationPolicy: HOUSE_NET_WORTH_VALUATION_POLICY, snapshots,
    summary: {
      currentNetWorthUnits: current.toString(), liquidCreditsUnits: cash.toString(), depositPrincipalUnits: deposits.toString(),
      commodityValuationUnits: commodities.toString(), buildingsValuationUnits: buildings.toString(), debtUnits: debt.toString(),
      growthRatePct: initial > 0n ? Number(((current - initial) * 10000n) / initial) / 100 : 0,
      peakNetWorthUnits: peak.toString(), peakDay,
      assetAllocation: { cashPct: pct(cash, base), depositsPct: pct(deposits, base), commoditiesPct: pct(commodities, base), buildingsPct: pct(buildings, base), debtPct: pct(debt, base) },
    },
  };
}

export async function recordDailyNetWorthSnapshot(repository: PostgresRepository, humanId: string, gameDay: number, correlationId = `net-worth-${humanId}-${gameDay}`) {
  return repository.transaction(async (tx) => {
    const human = (await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE', [humanId])).rows[0];
    if (!human?.house_id) throw new Error('Active House is required for net-worth history');
    const houseId = human.house_id;
    const [wallet, deposits, loans, resources, prices, buildings] = await Promise.all([
      tx.query(`SELECT COALESCE(a.balance_units, 0)::TEXT AS units FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [houseId]),
      tx.query(`SELECT COALESCE(SUM(d.principal_units), 0)::TEXT AS units FROM bank_deposits d JOIN owner_registry o ON o.economic_id = d.depositor_economic_id WHERE o.id = $1 AND d.status = 'ACTIVE'`, [houseId]),
      tx.query(`SELECT COALESCE(SUM(l.outstanding_principal_units + l.accrued_interest_units), 0)::TEXT AS units FROM bank_loans l JOIN owner_registry o ON o.economic_id = l.borrower_economic_id WHERE o.id = $1 AND l.status NOT IN ('PAID','CANCELLED')`, [houseId]),
      tx.query(`SELECT asset.code AS resource, a.balance_units::TEXT AS quantity_units FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id JOIN economic_assets asset ON asset.id = a.asset_id WHERE o.id = $1 AND asset.asset_kind = 'RESOURCE' AND a.account_type = 'INVENTORY'`, [houseId]),
      tx.query(`SELECT LOWER(i.symbol) AS resource, s.last_clearing_price_units::TEXT AS price_units FROM market_instruments i JOIN market_instrument_state s ON s.instrument_id = i.id WHERE LOWER(i.status) = 'active' AND s.last_clearing_price_units IS NOT NULL`),
      tx.query(`SELECT COALESCE(SUM(c.construction_credit_units), 0)::TEXT AS units FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id WHERE b.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'HOUSE') AND b.status <> 'DESTROYED'`, [houseId]),
    ]);
    const priceMap = new Map<string, bigint>(prices.rows.map((row) => [String(row.resource).toLowerCase(), units(row.price_units)]));
    let commodityValuation = 0n;
    for (const row of resources.rows) commodityValuation += units(row.quantity_units) * (priceMap.get(String(row.resource).toLowerCase()) ?? 0n);
    const liquid = units(wallet.rows[0]?.units); const depositPrincipal = units(deposits.rows[0]?.units); const debt = units(loans.rows[0]?.units); const buildingsValuation = units(buildings.rows[0]?.units);
    const total = liquid + depositPrincipal + commodityValuation + buildingsValuation - debt;
    const id = `NW-${houseId}-${gameDay}-${correlationId}`;
    const result = await tx.query<HouseNetWorthSnapshot>(`INSERT INTO net_worth_snapshots (id, house_id, current_human_id, game_day, liquid_credits_units, deposit_principal_units, commodity_valuation_units, buildings_valuation_units, debt_units, total_net_worth_units, valuation_policy)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (house_id, game_day) DO UPDATE SET current_human_id = EXCLUDED.current_human_id, liquid_credits_units = EXCLUDED.liquid_credits_units, deposit_principal_units = EXCLUDED.deposit_principal_units, commodity_valuation_units = EXCLUDED.commodity_valuation_units, buildings_valuation_units = EXCLUDED.buildings_valuation_units, debt_units = EXCLUDED.debt_units, total_net_worth_units = EXCLUDED.total_net_worth_units, valuation_policy = EXCLUDED.valuation_policy RETURNING *`, [id, houseId, humanId, gameDay, liquid.toString(), depositPrincipal.toString(), commodityValuation.toString(), buildingsValuation.toString(), debt.toString(), total.toString(), HOUSE_NET_WORTH_VALUATION_POLICY.code]);
    return { ok: true, snapshot: result.rows[0] };
  });
}
