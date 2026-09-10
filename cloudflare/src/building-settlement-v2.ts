import type { PostgresRepository } from './repository.ts';

type Account = {
  owner_id: string;
  economic_id: string;
  account_id: string;
  asset_id: number;
  account_type: number;
  balance: string;
};

type Building = {
  id: string;
  owner_id: string | null;
  city_id: string | null;
  ownership_class: string | null;
  operating_policy: string | null;
  condition: string;
  auto_repair_enabled: boolean | null;
  resource_output_type: string | null;
  resource_output_amount: string | null;
  upkeep_energy: string;
  upkeep_food: string;
  upkeep_materials: string;
  upkeep_components: string;
  upkeep_compute: string;
  daily_operating_credits: string;
  output_credits: string;
  output_energy: string;
  output_food: string;
  output_materials: string;
  output_components: string;
  output_compute: string;
  economic_output_multiplier: string | null;
  economic_cost_multiplier: string | null;
  economic_decay_multiplier: string | null;
};

export type BuildingSettlementResult = {
  buildingId: string;
  canOperate: boolean;
  requestedUpkeep: Record<string, number>;
  paidUpkeep: Record<string, number>;
  productionOutput: Record<string, number>;
  serviceCapacity: number;
  customerDemand: number;
  actualSales: number;
  actualRevenue: number;
  customerDemand: number;
  actualRevenue: number;
  conditionDelta: number;
  repairCost: Record<string, number>;
};

type Effect = {
  ownerEconomicId: string;
  shard: number;
  accountId: string;
  assetId: number;
  delta: bigint;
  reasonCode: string;
  sourceId: string;
};

const ASSET_IDS: Record<string, number> = {
  CREDIT: 1,
  MATERIAL: 2,
  COMPONENTS: 3,
  ENERGY: 4,
  COMPUTE: 5,
  FOOD: 6,
};
const SCALES: Record<number, number> = { 1: 100, 2: 1_000_000, 3: 1_000_000, 4: 1_000_000, 5: 1_000_000, 6: 1_000_000 };
const RESOURCE_ASSETS: Record<string, number> = { energy: 4, food: 6, material: 2, materials: 2, components: 3, compute: 5 };

function units(value: number, assetId: number): bigint {
  return BigInt(Math.round(value * SCALES[assetId]));
}

function addEffect(effects: Effect[], account: Account | undefined, delta: bigint, reasonCode: string, sourceId: string): void {
  if (delta === 0n) return;
  if (!account) throw new Error(`Missing V2 economic account for ${reasonCode} (${sourceId})`);
  effects.push({ ownerEconomicId: account.economic_id, shard: Number(BigInt(account.economic_id) % 64n), accountId: account.account_id, assetId: account.asset_id, delta, reasonCode, sourceId });
}

function key(ownerId: string, assetId: number): string {
  return `${ownerId}:${assetId}`;
}

function calculateResult(input: {
  building: Building;
  ownerClass: string;
  condition: number;
  upkeep: Record<string, number>;
  available: Record<string, number>;
  productionOutput: Record<string, number>;
  serviceCapacity: number;
  actualSales: number;
  repaired: boolean;
}): BuildingSettlementResult {
  const paidUpkeep: Record<string, number> = {};
  let canOperate = true;
  for (const [resource, requested] of Object.entries(input.upkeep)) {
    const paid = Math.min(requested, Math.max(0, input.available[resource] ?? 0));
    paidUpkeep[resource] = paid;
    if (paid + 1e-9 < requested) canOperate = false;
  }
  if (!canOperate) {
    return {
      buildingId: input.building.id,
      canOperate: false,
      requestedUpkeep: input.upkeep,
      paidUpkeep,
      productionOutput: {},
      serviceCapacity: input.serviceCapacity,
      customerDemand: 0,
      actualSales: 0,
      actualRevenue: 0,
      conditionDelta: -(input.repaired ? 6 : 8),
      repairCost: input.repaired ? { [input.ownerClass === 'civic' ? 'materials' : 'components']: 1 } : {},
    };
  }
  return {
    buildingId: input.building.id,
    canOperate: true,
    requestedUpkeep: input.upkeep,
    paidUpkeep,
    productionOutput: input.productionOutput,
    serviceCapacity: input.serviceCapacity,
    customerDemand: 0,
    actualSales: input.actualSales,
    actualRevenue: input.actualSales,
    conditionDelta: -(input.repaired ? 1 : 1),
    repairCost: input.repaired ? { [input.ownerClass === 'civic' ? 'materials' : 'components']: 1 } : {},
  };
}

async function insertEffects(tx: PostgresRepository, day: number, effects: Effect[]): Promise<void> {
  if (effects.length === 0) return;
  const values: unknown[] = [];
  const rows: string[] = [];
  for (const effect of effects) {
    const offset = values.length;
    rows.push(`($${offset + 1}, 'building_settlement', $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6}, $${offset + 7}, $${offset + 8})`);
    values.push(day, effect.shard, effect.ownerEconomicId, effect.accountId, effect.assetId, effect.delta.toString(), effect.reasonCode, effect.sourceId);
  }
  await tx.query(
    `INSERT INTO settlement_effects
      (game_day, phase, shard, owner_economic_id, account_id, asset_id, delta, reason_code, source_id)
     VALUES ${rows.join(',')}`,
    values,
  );
}

/**
 * V2 building settlement boundary. It calculates and resolves each building
 * before netting, but never mutates economic_accounts or legacy balance tables.
 */
export async function settleBuildingUpkeepAndRevenueV2(tx: PostgresRepository, day: number): Promise<void> {
  const buildings = await tx.query<Building>(`SELECT
      b.id, b.owner_id, b.city_id, b.ownership_class, b.operating_policy, b.condition,
      b.auto_repair_enabled, b.resource_output_type, b.resource_output_amount,
      COALESCE(bc.upkeep_energy, b.upkeep_energy, 0) AS upkeep_energy,
      COALESCE(bc.upkeep_food, b.upkeep_food, 0) AS upkeep_food,
      COALESCE(bc.upkeep_materials, b.upkeep_materials, 0) AS upkeep_materials,
      COALESCE(bc.upkeep_components, b.upkeep_components, 0) AS upkeep_components,
      COALESCE(bc.upkeep_compute, b.upkeep_compute, 0) AS upkeep_compute,
      COALESCE(bc.operating_credits, b.daily_operating_credits, 0) AS daily_operating_credits,
      COALESCE(bc.output_credits, CASE WHEN b.resource_output_type = 'credits' THEN b.resource_output_amount ELSE 0 END, 0) AS output_credits,
      COALESCE(bc.output_energy, CASE WHEN b.resource_output_type = 'energy' THEN b.resource_output_amount ELSE 0 END, 0) AS output_energy,
      COALESCE(bc.output_food, CASE WHEN b.resource_output_type = 'food' THEN b.resource_output_amount ELSE 0 END, 0) AS output_food,
      COALESCE(bc.output_materials, CASE WHEN b.resource_output_type IN ('material','materials') THEN b.resource_output_amount ELSE 0 END, 0) AS output_materials,
      COALESCE(bc.output_components, CASE WHEN b.resource_output_type = 'components' THEN b.resource_output_amount ELSE 0 END, 0) AS output_components,
      COALESCE(bc.output_compute, CASE WHEN b.resource_output_type = 'compute' THEN b.resource_output_amount ELSE 0 END, 0) AS output_compute,
      (SELECT MAX(e.effective_output_multiplier)::NUMERIC FROM earth_calculate_building_economics(b.id) e) AS economic_output_multiplier,
      (SELECT MAX(e.effective_cost_multiplier)::NUMERIC FROM earth_calculate_building_economics(b.id) e) AS economic_cost_multiplier,
      (SELECT p.decay_multiplier FROM economic_policy_rules p WHERE p.code = b.operating_policy) AS economic_decay_multiplier
    FROM buildings b
    LEFT JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE b.status = 'active'
    ORDER BY b.id`, [day]);

  const ownerIds = [...new Set(buildings.rows.flatMap((b) => [b.owner_id, b.city_id]).filter((id): id is string => Boolean(id)))];
  const accountRows = await tx.query<Account>(
    `SELECT o.id AS owner_id, o.economic_id::TEXT AS economic_id, a.id::TEXT AS account_id,
            a.asset_id, a.account_type, a.balance::TEXT
       FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      WHERE (o.id = ANY($1::TEXT[]) OR o.id = 'SYSTEM') AND a.status = 'active'`,
    [ownerIds],
  );
  const accounts = new Map<string, Account>();
  const byOwnerAsset = new Map<string, Account>();
  const available = new Map<string, number>();
  for (const account of accountRows.rows) {
    available.set(key(account.owner_id, account.asset_id), Number(account.balance) / SCALES[account.asset_id]);
    const existing = accounts.get(`${account.owner_id}:${account.asset_id}:${account.account_type}`);
    if (!existing || account.account_type === 7 || account.account_type === 8 || account.account_type === 9) accounts.set(`${account.owner_id}:${account.asset_id}:${account.account_type}`, account);
    if (account.account_type === 1 || account.account_type === 2 || account.account_type === 3 || account.account_type === 5) byOwnerAsset.set(key(account.owner_id, account.asset_id), account);
  }
  const residents = new Map<string, Account[]>();
  const residentRows = await tx.query<{ city_id: string; human_id: string }>(
    `SELECT m.city_id, m.human_id FROM memberships m JOIN humans h ON h.id = m.human_id
      WHERE h.life_status = 'active' AND m.city_id = ANY($1::TEXT[])`, [ownerIds]);
  const residentIds = [...new Set(residentRows.rows.map((r) => r.human_id))];
  if (residentIds.length > 0) {
    const extra = await tx.query<Account>(`SELECT o.id AS owner_id, o.economic_id::TEXT AS economic_id, a.id::TEXT AS account_id,
      a.asset_id, a.account_type, a.balance::TEXT FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      WHERE o.id = ANY($1::TEXT[]) AND a.asset_id = 1 AND a.account_type IN (1,3,5) AND a.status = 'active'`, [residentIds]);
    for (const row of extra.rows) {
      byOwnerAsset.set(key(row.owner_id, row.asset_id), row);
      available.set(key(row.owner_id, row.asset_id), Number(row.balance) / SCALES[row.asset_id]);
    }
    for (const row of residentRows.rows) {
      const account = byOwnerAsset.get(key(row.human_id, 1));
      if (account) residents.set(row.city_id, [...(residents.get(row.city_id) ?? []), account]);
    }
  }

  const effects: Effect[] = [];
  const system = (assetId: number, accountType: number) => accounts.get(`SYSTEM:${assetId}:${accountType}`);

  for (const building of buildings.rows) {
    const ownerClass = (building.ownership_class ?? 'private').toLowerCase();
    const economicOwner = ownerClass === 'civic' ? building.city_id : building.owner_id;
    if (!economicOwner) continue;
    const costMultiplier = Number(building.economic_cost_multiplier ?? 1);
    const outputMultiplier = Number(building.economic_output_multiplier ?? 1);
    const upkeep: Record<string, number> = {
      energy: Number(building.upkeep_energy) * costMultiplier,
      food: Number(building.upkeep_food) * costMultiplier,
      materials: Number(building.upkeep_materials) * costMultiplier,
      components: Number(building.upkeep_components) * costMultiplier,
      compute: Number(building.upkeep_compute) * costMultiplier,
    };
    const productionOutput: Record<string, number> = {};
    for (const [name, value] of Object.entries({ ENERGY: building.output_energy, FOOD: building.output_food, MATERIAL: building.output_materials, COMPONENTS: building.output_components, COMPUTE: building.output_compute })) {
      const amount = Number(value ?? 0) * outputMultiplier;
      if (amount > 0) productionOutput[name] = amount;
    }
    const serviceCapacity = Number(building.output_credits ?? 0) * outputMultiplier;
    const ownerCredit = byOwnerAsset.get(key(economicOwner, 1));
    const ops = accounts.get(`${building.city_id ?? 'SYSTEM'}:1:4`) ?? byOwnerAsset.get(key(building.city_id ?? 'SYSTEM', 1)) ?? ownerCredit;
    const revenueRecipient = ownerCredit;
    const repaired = Boolean(building.auto_repair_enabled) && Number(building.condition) < 80 && (available.get(key(economicOwner, ownerClass === 'civic' ? 2 : 3)) ?? 0) >= 1;
    if (repaired) {
      const repairAsset = ownerClass === 'civic' ? 2 : 3;
      available.set(key(economicOwner, repairAsset), (available.get(key(economicOwner, repairAsset)) ?? 0) - 1);
      addEffect(effects, byOwnerAsset.get(key(economicOwner, repairAsset)), -units(1, repairAsset), 'building_repair_cost', building.id);
      addEffect(effects, system(repairAsset, 8), units(1, repairAsset), 'building_repair_consumption', building.id);
    }
    const ownerAvailable = { ...Object.fromEntries(Object.entries(RESOURCE_ASSETS).map(([name, assetId]) => [name, available.get(key(economicOwner, assetId)) ?? 0])) };
    const opCost = Number(building.daily_operating_credits) * costMultiplier;
    const physicalResult = calculateResult({ building, ownerClass, condition: Number(building.condition), upkeep, available: ownerAvailable, productionOutput, serviceCapacity, actualSales: 0, repaired });
    const result = physicalResult.canOperate && (available.get(key(economicOwner, 1)) ?? 0) >= opCost
      ? physicalResult
      : { ...physicalResult, canOperate: false, productionOutput: {}, customerDemand: 0, actualSales: 0, actualRevenue: 0, conditionDelta: -(repaired ? 6 : 8) };
    if (!result.canOperate) {
      const finalCondition = Math.max(0, Number(building.condition) + result.conditionDelta);
      await tx.query('UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [finalCondition, building.id]);
    } else {
      for (const [resource, amount] of Object.entries(result.paidUpkeep)) {
        const assetId = RESOURCE_ASSETS[resource];
        available.set(key(economicOwner, assetId), (available.get(key(economicOwner, assetId)) ?? 0) - amount);
        addEffect(effects, byOwnerAsset.get(key(economicOwner, assetId)), -units(amount, assetId), 'building_physical_upkeep', building.id);
        addEffect(effects, system(assetId, 8), units(amount, assetId), 'building_physical_consumption', building.id);
      }
      const opUnits = units(opCost, 1);
      available.set(key(economicOwner, 1), (available.get(key(economicOwner, 1)) ?? 0) - opCost);
      addEffect(effects, ownerCredit, -opUnits, 'building_operating_cost', building.id);
      addEffect(effects, ops, opUnits, 'building_operating_revenue', building.id);

      // Demand is resolved against each customer's remaining V2 wallet before
      // any effects are netted. This preserves partial-payment semantics.
      const creditOutput = result.serviceCapacity;
      const buyers = residents.get(building.city_id ?? '') ?? [];
      let demand = 0;
      if (creditOutput > 0 && buyers.length > 0) {
        const due = units(creditOutput / Math.max(1, buyers.length), 1);
        for (const buyer of buyers) {
          const buyerAvailable = available.get(key(buyer.owner_id, 1)) ?? 0;
          const paid = Math.min(due, units(buyerAvailable, 1));
          if (paid <= 0n) continue;
          available.set(key(buyer.owner_id, 1), buyerAvailable - Number(paid) / SCALES[1]);
          addEffect(effects, buyer, -paid, 'building_customer_demand', building.id);
          addEffect(effects, revenueRecipient, paid, 'building_customer_payment', building.id);
          demand += Number(paid) / SCALES[1];
        }
      }
      result.customerDemand = demand;
      result.actualSales = demand;
      result.actualRevenue = demand;
      for (const [asset, amount] of Object.entries(result.productionOutput)) {
        const assetId = ASSET_IDS[asset];
        const recipient = byOwnerAsset.get(key(economicOwner, assetId));
        addEffect(effects, system(assetId, 7), -units(amount, assetId), 'building_output_issuance', building.id);
        addEffect(effects, recipient, units(amount, assetId), 'building_output', building.id);
      }
      const conditionDelta = -(Number(building.economic_decay_multiplier ?? 1));
      await tx.query('UPDATE buildings SET condition = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [Math.max(0, Number(building.condition) + conditionDelta), building.id]);
    }
    await tx.query(`INSERT INTO building_settlement_journals
      (id, building_id, city_id, day, ownership_class, gross_revenue_crd, operating_costs_crd, net_surplus_crd,
       condition_start, condition_end, auto_repaired)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
      ON CONFLICT (building_id, day) DO UPDATE SET condition_end = EXCLUDED.condition_end, auto_repaired = EXCLUDED.auto_repaired`,
      [`JOURNAL-${building.id}-${day}`, building.id, building.city_id, day, ownerClass, result.actualSales, opCost, Math.max(0, result.actualSales - opCost), Number(building.condition), Math.max(0, Number(building.condition) + (result.canOperate ? -Number(building.economic_decay_multiplier ?? 1) : result.conditionDelta)), repaired]);
  }
  await insertEffects(tx, day, effects);
}
