import type { PostgresRepository } from './repository.ts';

type Building = {
  id: string;
  owner_economic_id: string;
  territory_id: string;
  ownership_scope: 'PRIVATE' | 'PUBLIC';
  operating_credit_units: string;
  resource_input_units: Record<string, number> | string;
  resource_output_units: Record<string, number> | string;
};
type Account = { id: string; asset_id: number; account_type: string; balance_units: string };

const ASSET_IDS: Record<string, number> = { CREDIT: 1, MATERIAL: 2, COMPONENTS: 3, ENERGY: 4, COMPUTE: 5, FOOD: 6 };
const RESOURCE_PRODUCTION_OWNER = 'ECON-RESOURCE-PRODUCTION';
const RESOURCE_CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';

function catalogUnits(value: unknown): Record<string, bigint> {
  const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : (value ?? {});
  return Object.fromEntries(Object.entries(parsed as Record<string, unknown>)
    .map(([asset, amount]) => [asset.toUpperCase(), BigInt(Math.max(0, Math.trunc(Number(amount))))]));
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
    `SELECT earth_post_transaction($1, $2, 1439, $3, $4, $5, 'building-settlement-v3', $6::JSONB)`,
    [correlationId, day, kind, sourceType, sourceId, JSON.stringify(entries.map((entry) => ({ account_id: entry.accountId, asset_id: entry.assetId, delta_units: entry.delta.toString(), reason_code: entry.reason })))],
  );
}

async function settlePrivateBuilding(tx: PostgresRepository, day: number, building: Building): Promise<void> {
  const input = catalogUnits(building.resource_input_units);
  const output = catalogUnits(building.resource_output_units);
  for (const [assetCode, amount] of Object.entries(input)) {
    if (amount <= 0n) continue;
    const assetId = ASSET_IDS[assetCode];
    if (!assetId || assetId === ASSET_IDS.CREDIT) throw new Error(`Private building has invalid resource input ${assetCode}`);
    const houseInventory = await account(tx, building.owner_economic_id, assetId, 'INVENTORY');
    const sink = await account(tx, RESOURCE_CONSUMPTION_OWNER, assetId, 'SYSTEM_ACCOUNT');
    await post(tx, day, `building:${building.id}:${day}:consume:${assetId}`, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', building.id, [
      { accountId: houseInventory.id, assetId, delta: -amount, reason: 'private_building_resource_input' },
      { accountId: sink.id, assetId, delta: amount, reason: 'private_building_resource_input' },
    ]);
  }
  for (const [assetCode, amount] of Object.entries(output)) {
    if (amount <= 0n) continue;
    const assetId = ASSET_IDS[assetCode];
    if (!assetId || assetId === ASSET_IDS.CREDIT) throw new Error(`Private building has invalid resource output ${assetCode}`);
    const houseInventory = await account(tx, building.owner_economic_id, assetId, 'INVENTORY');
    const source = await account(tx, RESOURCE_PRODUCTION_OWNER, assetId, 'SYSTEM_ACCOUNT');
    await post(tx, day, `building:${building.id}:${day}:produce:${assetId}`, 'RESOURCE_PRODUCTION', 'SYSTEM_PRODUCTION', building.id, [
      { accountId: source.id, assetId, delta: -amount, reason: 'private_building_resource_output' },
      { accountId: houseInventory.id, assetId, delta: amount, reason: 'private_building_resource_output' },
    ]);
  }
  const operatingCost = BigInt(Math.max(0, Math.trunc(Number(building.operating_credit_units))));
  if (operatingCost > 0n) {
    const wallet = await account(tx, building.owner_economic_id, ASSET_IDS.CREDIT, 'WALLET');
    const earthOperations = await account(tx, 'ECON-EARTH-001', ASSET_IDS.CREDIT, 'OPERATIONS');
    await post(tx, day, `building:${building.id}:${day}:private-credit`, 'ASSET_TRANSFER', 'SETTLEMENT', building.id, [
      { accountId: wallet.id, assetId: ASSET_IDS.CREDIT, delta: -operatingCost, reason: 'private_building_operating_expense' },
      { accountId: earthOperations.id, assetId: ASSET_IDS.CREDIT, delta: operatingCost, reason: 'private_building_operating_expense' },
    ]);
  }
}

async function settlePublicBuilding(tx: PostgresRepository, day: number, building: Building): Promise<void> {
  const operatingCost = BigInt(Math.max(0, Math.trunc(Number(building.operating_credit_units))));
  if (operatingCost <= 0n) return;
  const treasury = await account(tx, building.owner_economic_id, ASSET_IDS.CREDIT, 'TREASURY');
  const operations = await account(tx, building.owner_economic_id, ASSET_IDS.CREDIT, 'OPERATIONS');
  await post(tx, day, `building:${building.id}:${day}:public-credit`, 'CORPORATION_PUBLIC_SPENDING', 'CORPORATION', building.id, [
    { accountId: treasury.id, assetId: ASSET_IDS.CREDIT, delta: -operatingCost, reason: 'public_infrastructure_operating_expense' },
    { accountId: operations.id, assetId: ASSET_IDS.CREDIT, delta: operatingCost, reason: 'public_infrastructure_operating_expense' },
  ]);
}

export type BuildingSettlementResult = { privateBuildings: number; publicBuildings: number; territoriesRefreshed: number };

/** House private economy and Corporation public infrastructure are separate settlement paths. */
export async function settleBuildingUpkeepAndRevenueV2(tx: PostgresRepository, day: number): Promise<BuildingSettlementResult> {
  const buildings = await tx.query<Building>(
    `SELECT b.id, b.owner_economic_id, b.territory_id, c.ownership_scope,
            c.operating_credit_units, c.resource_input_units, c.resource_output_units
       FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id
      WHERE b.status = 'ACTIVE' ORDER BY b.id`,
  );
  const territories = new Set<string>();
  let privateBuildings = 0;
  let publicBuildings = 0;
  for (const building of buildings.rows) {
    if (building.ownership_scope === 'PUBLIC') {
      await settlePublicBuilding(tx, day, building);
      publicBuildings += 1;
      territories.add(building.territory_id);
    } else {
      await settlePrivateBuilding(tx, day, building);
      privateBuildings += 1;
    }
  }
  for (const territoryId of territories) await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [territoryId, day]);
  return { privateBuildings, publicBuildings, territoriesRefreshed: territories.size };
}
