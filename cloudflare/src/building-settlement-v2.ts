import type { PostgresRepository } from './repository.ts';
import { applyConditionStack } from './world-conditions.ts';

type Building = {
  id: string;
  owner_economic_id: string;
  territory_id: string;
  ownership_scope: 'PRIVATE' | 'PUBLIC';
  operating_credit_units: string;
  operating_input_units: Record<string, number> | string;
  operating_output_units: Record<string, number> | string;
  last_major_rebuild_game_day: string;
  design_life_days: string;
  overdue_burden_bps_per_day: string;
  maximum_burden_bps: string;
};
function ageBurden(building: Building, day: number): bigint {
  const age = day >= Number(building.last_major_rebuild_game_day) ? BigInt(day - Number(building.last_major_rebuild_game_day)) : 0n;
  const overdue = age > BigInt(building.design_life_days) ? age - BigInt(building.design_life_days) : 0n;
  return overdue === 0n ? 10000n : Math.min(BigInt(building.maximum_burden_bps), 10000n + overdue * BigInt(building.overdue_burden_bps_per_day));
}
type Account = { id: string; asset_id: number; account_type: string; balance_units: string };
type Shard = { shard?: number; shardCount?: number };
type ConditionRow = { scope_type: string; scope_id: string | null; effect_type: string; target_key: string; modifier_bps: number };
type ModifierResolver = (effectType: string, targetKey: string, territoryId: string, ownerEconomicId: string) => number[];

const ASSET_IDS: Record<string, number> = { CREDIT: 1, MATERIAL: 2, COMPONENTS: 3, ENERGY: 4, COMPUTE: 5, FOOD: 6 };
const RESOURCE_PRODUCTION_OWNER = 'ECON-RESOURCE-PRODUCTION';
const RESOURCE_CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';

function catalogUnits(value: unknown): Record<string, bigint> {
  const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : (value ?? {});
  return Object.fromEntries(Object.entries(parsed as Record<string, unknown>)
    .map(([asset, amount]) => [asset.toUpperCase(), nonNegativeUnits(amount)]));
}

/** PostgreSQL authoritative unit columns are integer units; never round through JS Number. */
function nonNegativeUnits(value: unknown): bigint {
  if (typeof value === 'bigint') return value < 0n ? 0n : value;
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new Error('Authoritative unit value must be a safe integer');
    return BigInt(Math.max(0, value));
  }
  const text = String(value ?? '').trim();
  if (!/^\d+$/.test(text)) throw new Error('Authoritative unit value must be a non-negative integer');
  return BigInt(text);
}

async function account(tx: PostgresRepository, ownerEconomicId: string, assetId: number, accountType: string): Promise<Account> {
  const result = await tx.query<Account>(
    `SELECT id::TEXT, asset_id, account_type, balance_units::TEXT
       FROM economic_accounts
      WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = $3 AND status = 'ACTIVE'
      FOR UPDATE`, [ownerEconomicId, assetId, accountType],
  );
  if (!result.rows[0]) throw new Error(`Missing active ${accountType} account for ${ownerEconomicId} asset ${assetId}`);
  return result.rows[0];
}

async function post(tx: PostgresRepository, day: number, correlationId: string, kind: string, sourceType: string, sourceId: string, entries: Array<{ accountId: string; assetId: number; delta: bigint; reason: string }>): Promise<void> {
  if (!entries.length) return;
  await tx.query(
    `SELECT earth_post_transaction($1, $2, 1439, $3, $4, $5, 'building-settlement-v4', $6::JSONB)`,
    [correlationId, day, kind, sourceType, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })))],
  );
}

async function loadModifierResolver(tx: PostgresRepository, day: number): Promise<ModifierResolver> {
  const conditions = (await tx.query<ConditionRow>(`SELECT scope_type, scope_id, effect_type, target_key, modifier_bps
    FROM world_conditions
   WHERE effective_from_game_day <= $1 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
     AND effect_type IN ('SUPPLY_MULTIPLIER', 'DEMAND_MULTIPLIER')
   ORDER BY scope_type, scope_id NULLS FIRST, target_key, id`, [day])).rows;
  const organizations = (await tx.query<{ economic_id: string; organization_id: string }>('SELECT economic_id, organization_id FROM organization_economies')).rows;
  const organizationByEconomic = new Map(organizations.map((row) => [row.economic_id, row.organization_id]));
  return (effectType, targetKey, territoryId, ownerEconomicId) => conditions
    .filter((condition) => condition.effect_type === effectType && (condition.target_key === targetKey || condition.target_key === '*'))
    .filter((condition) => condition.scope_type === 'WORLD'
      || (condition.scope_type === 'TERRITORY' && condition.scope_id === territoryId)
      || (condition.scope_type === 'ORGANIZATION' && condition.scope_id === organizationByEconomic.get(ownerEconomicId)))
    .map((condition) => Number(condition.modifier_bps));
}

function adjustedInputUnits(building: Building, modifiers: ModifierResolver): Record<string, bigint> {
  return Object.fromEntries(Object.entries(catalogUnits(building.operating_input_units)).map(([code, required]) => [
    code, applyConditionStack(required, modifiers('DEMAND_MULTIPLIER', code, building.territory_id, building.owner_economic_id)),
  ]));
}

function utilizationFor(building: Building, available: Map<number, bigint>, demand: Map<number, bigint>, modifiers: ModifierResolver): bigint {
  let utilization = 10000n;
  for (const [code, required] of Object.entries(adjustedInputUnits(building, modifiers))) {
    if (required <= 0n) continue;
    const assetId = ASSET_IDS[code];
    const total = demand.get(assetId) ?? 0n;
    const availableUnits = available.get(assetId) ?? 0n;
    if (total > 0n) utilization = Math.min(utilization, (availableUnits * 10000n) / total);
  }
  return utilization;
}

async function settlePrivateHouse(tx: PostgresRepository, day: number, houseEconomicId: string, buildings: Building[], modifiers: ModifierResolver): Promise<number> {
  const available = new Map<number, bigint>();
  const demand = new Map<number, bigint>();
  for (const building of buildings) {
    for (const [code, required] of Object.entries(adjustedInputUnits(building, modifiers))) {
      if (required <= 0n) continue;
      const assetId = ASSET_IDS[code];
      if (!assetId || assetId === ASSET_IDS.CREDIT) throw new Error(`Private building has invalid resource input ${code}`);
      demand.set(assetId, (demand.get(assetId) ?? 0n) + required);
    }
  }
  for (const assetId of demand.keys()) {
    const inventory = await account(tx, houseEconomicId, assetId, 'INVENTORY');
    available.set(assetId, BigInt(inventory.balance_units));
  }

  const inputEntries: Array<{ accountId: string; assetId: number; delta: bigint; reason: string }> = [];
  const outputEntries: Array<{ accountId: string; assetId: number; delta: bigint; reason: string }> = [];
  const journals: Array<{ building: Building; utilization: bigint; inputs: Record<string, string>; outputs: Record<string, string>; shortages: Record<string, string>; limiting: string[]; credit: bigint; status: string }> = [];
  const consumed = new Map<number, bigint>();
  const produced = new Map<number, bigint>();

  // All utilization decisions use the same opening snapshot. Produced units
  // are accumulated separately and cannot satisfy another building today.
  for (const building of buildings) {
    const utilization = utilizationFor(building, available, demand, modifiers);
    const inputs: Record<string, string> = {};
    const outputs: Record<string, string> = {};
    const shortages: Record<string, string> = {};
    const limiting: string[] = [];
    for (const [code, required] of Object.entries(adjustedInputUnits(building, modifiers))) {
      const units = (required * utilization) / 10000n;
      if (units < required) shortages[code] = (required - units).toString();
      const total = demand.get(ASSET_IDS[code]) ?? 0n;
      if (total > 0n && (available.get(ASSET_IDS[code]) ?? 0n) * 10000n / total === utilization) limiting.push(code);
      if (units <= 0n) continue;
      const assetId = ASSET_IDS[code];
      inputs[code] = units.toString();
      consumed.set(assetId, (consumed.get(assetId) ?? 0n) + units);
    }
    for (const [code, output] of Object.entries(catalogUnits(building.operating_output_units))) {
      const operated = (output * utilization) / 10000n;
      const units = applyConditionStack(operated, modifiers('SUPPLY_MULTIPLIER', code, building.territory_id, building.owner_economic_id));
      if (units <= 0n) continue;
      const assetId = ASSET_IDS[code];
      if (!assetId || assetId === ASSET_IDS.CREDIT) throw new Error(`Private building has invalid resource output ${code}`);
      outputs[code] = units.toString();
      produced.set(assetId, (produced.get(assetId) ?? 0n) + units);
    }
    const credit = (nonNegativeUnits(building.operating_credit_units) * utilization * ageBurden(building, day)) / 100000000n;
    journals.push({ building, utilization, inputs, outputs, shortages, limiting, credit, status: utilization === 10000n ? 'OPERATED' : utilization === 0n ? 'STARVED' : 'PARTIAL' });
  }

  for (const [assetId, units] of consumed) {
    if (units <= 0n) continue;
    const inventory = await account(tx, houseEconomicId, assetId, 'INVENTORY');
    const sink = await account(tx, RESOURCE_CONSUMPTION_OWNER, assetId, 'SYSTEM_ACCOUNT');
    inputEntries.push({ accountId: inventory.id, assetId, delta: -units, reason: 'private_building_operating_input' });
    inputEntries.push({ accountId: sink.id, assetId, delta: units, reason: 'private_building_operating_input' });
  }
  for (const [assetId, units] of produced) {
    if (units <= 0n) continue;
    const inventory = await account(tx, houseEconomicId, assetId, 'INVENTORY');
    const source = await account(tx, RESOURCE_PRODUCTION_OWNER, assetId, 'SYSTEM_ACCOUNT');
    outputEntries.push({ accountId: source.id, assetId, delta: -units, reason: 'private_building_operating_output' });
    outputEntries.push({ accountId: inventory.id, assetId, delta: units, reason: 'private_building_operating_output' });
  }
  if (inputEntries.length) await post(tx, day, `building-house:${houseEconomicId}:${day}:consume`, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', houseEconomicId, inputEntries);
  if (outputEntries.length) await post(tx, day, `building-house:${houseEconomicId}:${day}:produce`, 'RESOURCE_PRODUCTION', 'SYSTEM_PRODUCTION', houseEconomicId, outputEntries);

  const credit = journals.reduce((sum, row) => sum + row.credit, 0n);
  if (credit > 0n) {
    const wallet = await account(tx, houseEconomicId, ASSET_IDS.CREDIT, 'WALLET');
    const constructionSettlement = await account(tx, 'ECON-CONSTRUCTION-SETTLEMENT', ASSET_IDS.CREDIT, 'SYSTEM_ACCOUNT');
    await post(tx, day, `building-house:${houseEconomicId}:${day}:credit`, 'ASSET_TRANSFER', 'PRIVATE_BUILDING_OPERATION', houseEconomicId, [
      { accountId: wallet.id, assetId: ASSET_IDS.CREDIT, delta: -credit, reason: 'private_building_operating_expense' },
      { accountId: constructionSettlement.id, assetId: ASSET_IDS.CREDIT, delta: credit, reason: 'private_building_operating_expense' },
    ]);
  }
  for (const row of journals) {
    await tx.query(
      `INSERT INTO building_settlement_journals
        (building_id, house_economic_id, game_day, utilization_bps, input_units, output_units, operating_credit_units, status, limiting_resources, shortage_units)
       VALUES ($1,$2,$3,$4,$5::JSONB,$6::JSONB,$7,$8,$9::JSONB,$10::JSONB)
       ON CONFLICT (building_id, game_day) DO NOTHING`,
      [row.building.id, houseEconomicId, day, row.utilization.toString(), JSON.stringify(row.inputs), JSON.stringify(row.outputs), row.credit.toString(), row.status, JSON.stringify(row.limiting), JSON.stringify(row.shortages)],
    );
  }
  return buildings.length;
}

async function settlePublicBuilding(tx: PostgresRepository, day: number, building: Building): Promise<void> {
  const cost = (nonNegativeUnits(building.operating_credit_units) * ageBurden(building, day)) / 10000n;
  if (cost <= 0n) return;
  const treasury = await account(tx, building.owner_economic_id, ASSET_IDS.CREDIT, 'TREASURY');
  const operations = await account(tx, building.owner_economic_id, ASSET_IDS.CREDIT, 'OPERATIONS');
  await post(tx, day, `building:${building.id}:${day}:public-credit`, 'CORPORATION_PUBLIC_SPENDING', 'CORPORATION', building.id, [
    { accountId: treasury.id, assetId: ASSET_IDS.CREDIT, delta: -cost, reason: 'public_infrastructure_operating_expense' },
    { accountId: operations.id, assetId: ASSET_IDS.CREDIT, delta: cost, reason: 'public_infrastructure_operating_expense' },
  ]);
}

export type BuildingSettlementResult = { privateBuildings: number; publicBuildings: number; territoriesRefreshed: number };

export async function settleBuildingUpkeepAndRevenueV2(tx: PostgresRepository, day: number, shard: Shard = {}): Promise<BuildingSettlementResult> {
  const shardCount = Math.max(1, shard.shardCount ?? 1);
  const shardId = Math.max(0, shard.shard ?? 0);
  const buildings = await tx.query<Building>(
    `SELECT b.id, b.owner_economic_id, b.territory_id, c.ownership_scope,
            c.operating_credit_units,
            COALESCE(b.last_major_rebuild_game_day, b.started_game_day)::TEXT AS last_major_rebuild_game_day,
            r.design_life_days::TEXT,
            r.overdue_burden_bps_per_day::TEXT,
            r.maximum_burden_bps::TEXT,
            COALESCE(jsonb_object_agg(a.code, f.operating_input_units) FILTER (WHERE f.operating_input_units > 0), '{}'::jsonb) AS operating_input_units,
            COALESCE(jsonb_object_agg(a.code, f.operating_output_units) FILTER (WHERE f.operating_output_units > 0), '{}'::jsonb) AS operating_output_units
       FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id
       JOIN building_design_life_rules r ON r.catalog_id = b.catalog_id
       LEFT JOIN building_catalog_resource_flows f ON f.catalog_id = c.id
       LEFT JOIN economic_assets a ON a.id = f.asset_id
      WHERE b.status = 'ACTIVE'
        AND mod(abs(hashtextextended(b.owner_economic_id, 0)), $1) = $2
      GROUP BY b.id, b.owner_economic_id, b.territory_id, c.ownership_scope, c.operating_credit_units, b.last_major_rebuild_game_day, b.started_game_day, r.design_life_days, r.overdue_burden_bps_per_day, r.maximum_burden_bps
      ORDER BY b.owner_economic_id, b.id`, [shardCount, shardId],
  );
  const modifiers = await loadModifierResolver(tx, day);
  const territories = new Set<string>();
  const houses = new Map<string, Building[]>();
  let publicBuildings = 0;
  for (const building of buildings.rows) {
    territories.add(building.territory_id);
    if (building.ownership_scope === 'PUBLIC') {
      await settlePublicBuilding(tx, day, building);
      publicBuildings += 1;
    } else {
      const group = houses.get(building.owner_economic_id) ?? [];
      group.push(building);
      houses.set(building.owner_economic_id, group);
    }
  }
  let privateBuildings = 0;
  for (const [houseEconomicId, houseBuildings] of houses) privateBuildings += await settlePrivateHouse(tx, day, houseEconomicId, houseBuildings, modifiers);
  for (const territoryId of territories) await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [territoryId, day]);
  return { privateBuildings, publicBuildings, territoriesRefreshed: territories.size };
}
