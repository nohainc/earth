import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

export type TerritoryCapacity = {
  territory_id: string;
  game_day: number;
  active_house_count: number;
  house_capacity: number;
  population_capacity: number;
  private_slot_capacity: number;
  public_slot_capacity: number;
  private_slots_used: number;
  public_slots_used: number;
  housing_capacity: number;
  health_capacity: number;
  energy_capacity: number;
  connectivity_capacity: number;
  service_capacity: Record<string, number>;
};

export async function getTerritoryCapacity(repository: PostgresRepository, territoryId: string): Promise<Record<string, unknown>> {
  const territory = await repository.query('SELECT id, corporation_id, name, territory_type, status, is_primary FROM territories WHERE id = $1', [territoryId]);
  if (!territory.rows[0]) throw new Error('Territory not found');
  const state = await repository.query<TerritoryCapacity>('SELECT * FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
  return { territory: territory.rows[0], capacity: state.rows[0] ?? null };
}

type ConstructionRequirement = { code: string; asset_id: number; required_units: string; available_units: string; missing_units: string };

async function loadConstructionRequirements(
  tx: PostgresRepository,
  catalogId: string,
  ownerEconomicId: string,
  isPublic: boolean,
): Promise<ConstructionRequirement[]> {
  const rows = await tx.query<{ code: string; asset_id: number; required_units: string; available_units: string }>(
    `SELECT asset.code, asset.id AS asset_id, flow.construction_units::TEXT AS required_units,
            COALESCE(account.balance_units, 0)::TEXT AS available_units
       FROM building_catalog_resource_flows flow
       JOIN economic_assets asset ON asset.id = flow.asset_id AND asset.asset_kind = 'RESOURCE'
       LEFT JOIN economic_accounts account
         ON account.owner_economic_id = $2 AND account.asset_id = flow.asset_id
        AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE flow.catalog_id = $1 AND flow.construction_units > 0
      ORDER BY asset.id`, [catalogId, ownerEconomicId],
  );
  if (isPublic) return [];
  return rows.rows.map((row) => {
    const required = BigInt(row.required_units);
    const available = BigInt(row.available_units);
    return { ...row, missing_units: (required > available ? required - available : 0n).toString() };
  });
}

export async function getConstructionQuote(
  repository: PostgresRepository,
  input: { ownerId: string; territoryId: string; buildingType: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const territory = (await tx.query<{ corporation_id: string }>("SELECT corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE'", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    const owner = (await tx.query<{ house_id: string; economic_id: string }>(
      `SELECT h.house_id, o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
        WHERE h.id = $1 AND h.status = 'ACTIVE'`, [input.ownerId])).rows[0];
    if (!owner) throw new Error('House economic owner not found');
    const membership = (await tx.query("SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [owner.house_id, territory.corporation_id])).rows[0];
    if (!membership) throw new Error('House must belong to the Territory Corporation');
    const catalog = (await tx.query<{ id: string; code: string; ownership_scope: 'PRIVATE' | 'PUBLIC'; construction_credit_units: string }>(
      `SELECT id, code, ownership_scope, construction_credit_units FROM building_catalog
        WHERE (id = $1 OR code = $1 OR lower(code) = lower($1)) LIMIT 1`, [input.buildingType])).rows[0];
    if (!catalog) throw new Error('Unknown building blueprint');
    const isPublic = catalog.ownership_scope === 'PUBLIC';
    const economicOwner = isPublic ? (await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'CORPORATION'", [territory.corporation_id])).rows[0]?.economic_id : owner.economic_id;
    if (!economicOwner) throw new Error(`${isPublic ? 'Corporation' : 'House'} economic owner not found`);
    const credit = (await tx.query<{ balance_units: string }>(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE'`, [economicOwner, isPublic ? 'TREASURY' : 'WALLET'])).rows[0]?.balance_units ?? '0';
    const requirements = await loadConstructionRequirements(tx, catalog.id, economicOwner, isPublic);
    return {
      catalog: { id: catalog.id, code: catalog.code, ownershipScope: catalog.ownership_scope },
      requirements: {
        CREDIT: { required_units: catalog.construction_credit_units, available_units: credit, missing_units: (BigInt(catalog.construction_credit_units) > BigInt(credit) ? BigInt(catalog.construction_credit_units) - BigInt(credit) : 0n).toString() },
        ...Object.fromEntries(requirements.map((item) => [item.code, { required_units: item.required_units, available_units: item.available_units, missing_units: item.missing_units }])),
      },
    };
  });
}

export async function purchaseBuildingInTerritory(
  repository: PostgresRepository,
  input: { ownerId: string; territoryId: string; buildingType: string; name: string; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]?.source_id) return { ok: true, alreadyProcessed: true, building: (await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.rows[0].source_id])).rows[0], correlationId: input.correlationId };

    const territory = (await tx.query<{ id: string; corporation_id: string }>("SELECT id, corporation_id FROM territories WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.territoryId])).rows[0];
    if (!territory) throw new Error('Territory not found or inactive');
    const owner = (await tx.query<{ house_id: string; economic_id: string }>(
      `SELECT h.house_id, o.economic_id
         FROM humans h JOIN owner_registry o ON o.id = h.house_id AND o.owner_type = 'HOUSE'
        WHERE h.id = $1 AND h.status = 'ACTIVE'`, [input.ownerId],
    )).rows[0];
    if (!owner) throw new Error('House economic owner not found');
    const membership = (await tx.query(
      "SELECT 1 FROM house_affiliations WHERE house_id = $1 AND corporation_id = $2 AND status = 'ACTIVE'", [owner.house_id, territory.corporation_id],
    )).rows[0];
    if (!membership) throw new Error('House must belong to the Territory Corporation');
    const catalog = (await tx.query<{ id: string; code: string; ownership_scope: 'PRIVATE' | 'PUBLIC'; construction_credit_units: string; slot_footprint: number; service_type: string | null }>(
      `SELECT id, code, ownership_scope, construction_credit_units, slot_footprint, service_type FROM building_catalog
        WHERE (id = $1 OR code = $1 OR lower(code) = lower($1)) LIMIT 1`, [input.buildingType],
    )).rows[0];
    if (!catalog) throw new Error('Unknown building blueprint');
    const isPublic = catalog.ownership_scope === 'PUBLIC';
    const ownerEconomicId = isPublic
      ? (await tx.query<{ economic_id: string }>(
        `SELECT o.economic_id FROM owner_registry o
          WHERE o.id = $1 AND o.owner_type = 'CORPORATION'`, [territory.corporation_id],
      )).rows[0]?.economic_id
      : owner.economic_id;
    if (!ownerEconomicId) throw new Error(`${isPublic ? 'Corporation' : 'House'} economic owner not found`);
    const world = (await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'")).rows[0];
    const gameDay = Number(world?.game_day ?? 1);
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [input.territoryId, gameDay]);
    const projection = (await tx.query<{ private_slot_capacity: string; private_slots_used: string; public_slot_capacity: string; public_slots_used: string }>(
      'SELECT private_slot_capacity, private_slots_used, public_slot_capacity, public_slots_used FROM territory_capacity_state WHERE territory_id = $1 FOR UPDATE', [input.territoryId],
    )).rows[0];
    if (!projection) throw new Error('Territory capacity projection is unavailable');
    const availableSlots = isPublic
      ? Number(projection.public_slot_capacity) - Number(projection.public_slots_used)
      : Number(projection.private_slot_capacity) - Number(projection.private_slots_used);
    if (availableSlots < Number(catalog.slot_footprint)) throw new Error(`Territory ${isPublic ? 'public' : 'private'} capacity exceeded`);
    const wallet = (await tx.query<{ id: string; balance_units: string }>(
      `SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a
        WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type = $2 AND a.status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, isPublic ? 'TREASURY' : 'WALLET'],
    )).rows[0];
    const constructionDestination = (await tx.query<{ id: string }>(
      `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND o.owner_type = 'SYSTEM'
          AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`,
    )).rows[0];
    const cost = BigInt(catalog.construction_credit_units);
    if (!wallet || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for construction');
    if (!constructionDestination) throw new Error('Construction settlement destination is not configured');
    const constructionRequirements = await loadConstructionRequirements(tx, catalog.id, ownerEconomicId, isPublic);
    const missing = constructionRequirements.find((item) => BigInt(item.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for construction; missing ${missing.missing_units}`);
    const resourceAccounts = await Promise.all(constructionRequirements.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>(
        `SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, item.asset_id])).rows[0],
      sink: (await tx.query<{ id: string }>(
        `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
          WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'`, [item.asset_id])).rows[0],
    })));
    if (resourceAccounts.some((item) => !item.account || !item.sink)) throw new Error('Construction resource settlement accounts are not provisioned');
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query(
      `SELECT earth_post_transaction($1, $2, $3, 'ASSET_TRANSFER', $4, $5, 'construction-credit-v1', $6::JSONB)`,
      [input.correlationId, gameDay, Number(world?.game_minute ?? 0), isPublic ? 'PUBLIC_INFRASTRUCTURE_CONSTRUCTION' : 'PRIVATE_CONSTRUCTION', buildingId, JSON.stringify([
        { account_id: wallet.id, delta_units: (-cost).toString(), asset_id: 1 },
        { account_id: constructionDestination.id, delta_units: cost.toString(), asset_id: 1 },
      ])],
    );
    if (resourceAccounts.length) {
      await tx.query(
        `SELECT earth_post_transaction($1, $2, $3, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', $4, 'building-territory-v3', $5::JSONB)`,
        [`construction:${input.correlationId}:resources`, gameDay, Number(world?.game_minute ?? 0), buildingId, JSON.stringify(resourceAccounts.flatMap((item) => [
          { account_id: item.account!.id, asset_id: item.asset_id, delta_units: (-BigInt(item.required_units)).toString(), reason_code: 'private_construction_resource_input' },
          { account_id: item.sink!.id, asset_id: item.asset_id, delta_units: BigInt(item.required_units).toString(), reason_code: 'private_construction_resource_input' },
        ]))],
      );
    }
    await tx.query(
      `INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, started_game_day)
       VALUES ($1, $2, $3, $4, 'ACTIVE', $5)`, [buildingId, ownerEconomicId, input.territoryId, catalog.id, gameDay],
    );
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [input.territoryId, gameDay]);
    await createGameEvent(tx, {
      id: `BUILDING-ACQUIRED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_ACQUIRED', gameDay,
      actorHumanId: input.ownerId, subjectType: 'BUILDING', subjectId: buildingId,
      title: `${catalog.code} acquired in Territory`,
      details: { buildingId, catalogId: catalog.id, territoryId: input.territoryId, ownerEconomicId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE' },
      correlationId: input.correlationId,
    });
    return { ok: true, building: (await tx.query('SELECT * FROM buildings WHERE id = $1', [buildingId])).rows[0], ownerType: isPublic ? 'CORPORATION' : 'HOUSE', capacity: (await tx.query('SELECT * FROM territory_capacity_state WHERE territory_id = $1', [input.territoryId])).rows[0], correlationId: input.correlationId };
  });
}
