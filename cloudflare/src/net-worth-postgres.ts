export interface NetWorthSnapshot {
  id: string;
  human_id: string;
  game_day: number;
  liquid_credits: string | number;
  commodity_valuation: string | number;
  equity_valuation: string | number;
  real_estate_valuation: string | number;
  total_net_worth: string | number;
  created_at: string;
}

export interface NetWorthSummary {
  currentNetWorth: number;
  liquidCredits: number;
  commodityValuation: number;
  equityValuation: number;
  realEstateValuation: number;
  growthRatePct: number;
  peakNetWorth: number;
  peakDay: number;
  assetAllocation: {
    cashPct: number;
    commodityPct: number;
    equityPct: number;
    realEstatePct: number;
  };
}

export async function getNetWorthHistory(
  client: any,
  humanId: string = 'H-0044'
): Promise<{
  ok: boolean;
  humanId: string;
  snapshots: NetWorthSnapshot[];
  summary: NetWorthSummary;
}> {
  const res = await client.query(
    `SELECT * FROM net_worth_snapshots
     WHERE human_id = $1
     ORDER BY game_day ASC
     LIMIT 60`,
    [humanId]
  );

  const snapshots: NetWorthSnapshot[] = res.rows;

  let currentNetWorth = 0;
  let liquidCredits = 0;
  let commodityValuation = 0;
  let equityValuation = 0;
  let realEstateValuation = 0;
  let growthRatePct = 0;
  let peakNetWorth = 0;
  let peakDay = 1;

  if (snapshots.length > 0) {
    const latest = snapshots[snapshots.length - 1];
    const first = snapshots[0];

    liquidCredits = Number(latest.liquid_credits) || 0;
    commodityValuation = Number(latest.commodity_valuation) || 0;
    equityValuation = Number(latest.equity_valuation) || 0;
    realEstateValuation = Number(latest.real_estate_valuation) || 0;
    currentNetWorth = Number(latest.total_net_worth) || (liquidCredits + commodityValuation + equityValuation + realEstateValuation);

    const initialTotal = Number(first.total_net_worth) || 1;
    growthRatePct = initialTotal > 0 ? Math.round(((currentNetWorth - initialTotal) / initialTotal) * 10000) / 100 : 0;

    for (const s of snapshots) {
      const tot = Number(s.total_net_worth);
      if (tot > peakNetWorth) {
        peakNetWorth = tot;
        peakDay = Number(s.game_day);
      }
    }
  }

  const safeTotal = currentNetWorth > 0 ? currentNetWorth : 1;
  const assetAllocation = {
    cashPct: Math.round((liquidCredits / safeTotal) * 1000) / 10,
    commodityPct: Math.round((commodityValuation / safeTotal) * 1000) / 10,
    equityPct: Math.round((equityValuation / safeTotal) * 1000) / 10,
    realEstatePct: Math.round((realEstateValuation / safeTotal) * 1000) / 10,
  };

  return {
    ok: true,
    humanId,
    snapshots,
    summary: {
      currentNetWorth,
      liquidCredits,
      commodityValuation,
      equityValuation,
      realEstateValuation,
      growthRatePct,
      peakNetWorth,
      peakDay,
      assetAllocation,
    },
  };
}

export async function recordDailyNetWorthSnapshot(
  client: any,
  humanId: string,
  gameDay: number
): Promise<{ ok: boolean; snapshot: NetWorthSnapshot }> {
  // 1. Fetch liquid credits
  const accRes = await client.query(
    `SELECT ab.balance FROM humans h
     JOIN account_balances ab ON h.account_id = ab.account_id
     WHERE h.id = $1`,
    [humanId]
  );
  const liquid = accRes.rows.length > 0 ? Number(accRes.rows[0].balance) : 0;

  // 2. Fetch commodity balances & approximate valuation
  const resBalances = await client.query(
    `SELECT resource, amount FROM resource_balances WHERE owner_id = $1`,
    [humanId]
  );
  const priceMap: Record<string, number> = { energy: 30, material: 45, compute: 60, food: 20 };
  let commodityVal = 0;
  for (const r of resBalances.rows) {
    const p = priceMap[r.resource] || 25;
    commodityVal += Number(r.amount) * p;
  }

  // 3. Approximate equity & real estate
  const equityVal = 25000.0;
  const realEstateVal = 15000.0;
  const total = liquid + commodityVal + equityVal + realEstateVal;

  const id = `NW-${humanId}-${gameDay}`;
  const upsertRes = await client.query(
    `INSERT INTO net_worth_snapshots (
       id, human_id, game_day, liquid_credits, commodity_valuation, equity_valuation, real_estate_valuation, total_net_worth
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (human_id, game_day) DO UPDATE SET
       liquid_credits = EXCLUDED.liquid_credits,
       commodity_valuation = EXCLUDED.commodity_valuation,
       equity_valuation = EXCLUDED.equity_valuation,
       real_estate_valuation = EXCLUDED.real_estate_valuation,
       total_net_worth = EXCLUDED.total_net_worth
     RETURNING *`,
    [id, humanId, gameDay, liquid, commodityVal, equityVal, realEstateVal, total]
  );

  return {
    ok: true,
    snapshot: upsertRes.rows[0],
  };
}
