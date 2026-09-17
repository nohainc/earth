import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { toJsonSafe } from './json-safe.ts';
import { effectiveConstructionMinutes, loadConstructionRequirements } from './territory-capacity-postgres.ts';
import { quoteV5HouseCapacityChange, quoteV5CorporationCapacityChange } from './v5-capacity-postgres.ts';
import { rebuildV5CorporationSettlementProfile, refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';

type Catalog = {
  id: string;
  code: string;
  ownership_scope: 'PRIVATE' | 'PUBLIC';
  construction_credit_units: string;
  construction_minutes: number;
  slot_footprint: number;
};

async function ownerContext(tx: PostgresRepository, humanId: string): Promise<{ houseId: string; houseEconomicId: string; corporationId: string | null; corporationEconomicId: string | null }> {
  const row = (await tx.query<{ house_id: string; house_economic_id: string; corporation_id: string | null; corporation_economic_id: string | null }>(
    `SELECT h.house_id, house_owner.economic_id AS house_economic_id,
            ha.corporation_id, corp_owner.economic_id AS corporation_economic_id
       FROM humans h
       JOIN owner_registry house_owner ON house_owner.id = h.house_id AND house_owner.owner_type = 'HOUSE'
       LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
       LEFT JOIN owner_registry corp_owner ON corp_owner.id = ha.corporation_id AND corp_owner.owner_type = 'CORPORATION'
      WHERE h.id = $1 AND h.status = 'ACTIVE' LIMIT 1`, [humanId],
  )).rows[0];
  if (!row) throw new Error('Active House is required for V5 construction');
  return { houseId: row.house_id, houseEconomicId: row.house_economic_id, corporationId: row.corporation_id, corporationEconomicId: row.corporation_economic_id };
}

async function catalog(tx: PostgresRepository, buildingType: string): Promise<Catalog> {
  const row = (await tx.query<Catalog>(
    `SELECT id, code, ownership_scope, construction_credit_units, construction_minutes, slot_footprint
       FROM building_catalog
      WHERE id = $1 OR code = $1 OR lower(code) = lower($1) LIMIT 1`, [buildingType],
  )).rows[0];
  if (!row) throw new Error('Unknown building blueprint');
  return row;
}

export async function quoteV5Building(repository: PostgresRepository, input: { ownerId: string; buildingType: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const owner = await ownerContext(tx, input.ownerId);
    const blueprint = await catalog(tx, input.buildingType);
    const isPublic = blueprint.ownership_scope === 'PUBLIC';
    if (isPublic && (!owner.corporationId || !owner.corporationEconomicId)) throw new Error('Public V5 construction requires an active Corporation affiliation');
    if (isPublic && !(await tx.query(
      `SELECT 1 FROM institution_governance_roles
        WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
          AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`,
      [owner.corporationId, input.ownerId],
    )).rows[0]) throw new Error('Public V5 construction requires Corporation governance authorization');
    const ownerEconomicId = isPublic ? owner.corporationEconomicId : owner.houseEconomicId;
    const world = (await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'")).rows[0];
    const gameDay = Number(world?.game_day ?? 1);
    const delinquency = (await tx.query<{ status: string }>(
      `SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = $1 AND subject_id = $2`,
      [isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? owner.corporationId : owner.houseId],
    )).rows[0]?.status ?? 'CURRENT';
    const blocked = ['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency);
    const capacity = isPublic
      ? await quoteV5CorporationCapacityChange(tx, owner.corporationId, BigInt(blueprint.slot_footprint), gameDay)
      : await quoteV5HouseCapacityChange(tx, owner.houseId, BigInt(blueprint.slot_footprint), gameDay);
    const duration = await effectiveConstructionMinutes(tx, gameDay, null, blueprint.code, blueprint.construction_minutes);
    const requirements = await loadConstructionRequirements(tx, blueprint.id, ownerEconomicId, isPublic);
    const wallet = (await tx.query<{ balance_units: string }>(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE'`,
      [ownerEconomicId, isPublic ? 'TREASURY' : 'WALLET'],
    )).rows[0];
    const insufficientResources = requirements.filter((item) => BigInt(item.missing_units) > 0n).map((item) => ({ code: item.code, missingUnits: item.missing_units }));
    const blockers = [
      ...(blocked ? [`V5 capacity delinquency: ${delinquency}`] : []),
      ...(capacity?.available === false ? [String(capacity.reason ?? 'V5 capacity quote unavailable')] : []),
      ...(insufficientResources.length ? ['Insufficient construction resources'] : []),
      ...(wallet && BigInt(wallet.balance_units) < BigInt(blueprint.construction_credit_units) ? ['Insufficient Credits'] : []),
    ];
    return {
      ok: true,
      eligible: blockers.length === 0,
      blockers,
      ownerType: isPublic ? 'CORPORATION' : 'HOUSE',
      buildingType: blueprint.code,
      buildingCatalogId: blueprint.id,
      footprintUnits: blueprint.slot_footprint,
      creditCostUnits: blueprint.construction_credit_units,
      resourceRequirements: requirements.map((item) => ({ code: item.code, requiredUnits: item.required_units, availableUnits: item.available_units, missingUnits: item.missing_units })),
      effectiveConstructionMinutes: duration.minutes,
      expectedCompletionGameDay: gameDay + Math.max(1, Math.ceil(duration.minutes / 1440)),
      capacity,
      delinquencyStatus: delinquency,
      generatedFrom: 'postgres-canonical-building-catalog-v5',
    };
  });
}

/** V5 construction command using pooled Corporation capacity, without placement. */
export async function purchaseV5Building(repository: PostgresRepository, input: { ownerId: string; buildingType: string; name: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, building: toJsonSafe((await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.source_id])).rows[0]), correlationId: input.correlationId };
    const owner = await ownerContext(tx, input.ownerId);
    const blueprint = await catalog(tx, input.buildingType);
    const isPublic = blueprint.ownership_scope === 'PUBLIC';
    if (isPublic && (!owner.corporationId || !owner.corporationEconomicId)) throw new Error('Public V5 construction requires an active Corporation affiliation');
    const ownerEconomicId = isPublic ? owner.corporationEconomicId : owner.houseEconomicId;
    const currentWorld = (await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'")).rows[0];
    const gameDay = Number(currentWorld?.game_day ?? 1);
    const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = $1 AND subject_id = $2`, [isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? owner.corporationId : owner.houseId])).rows[0];
    if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency?.status ?? '')) throw new Error('V5 capacity delinquency blocks construction expansion');
    const capacity = isPublic
      ? await quoteV5CorporationCapacityChange(tx, owner.corporationId, BigInt(blueprint.slot_footprint), gameDay)
      : await quoteV5HouseCapacityChange(tx, owner.houseId, BigInt(blueprint.slot_footprint), gameDay);
    if (capacity && capacity.available === false) throw new Error(String(capacity.reason ?? 'V5 capacity quote unavailable'));
    const duration = await effectiveConstructionMinutes(tx, gameDay, null, blueprint.code, blueprint.construction_minutes);
    const wallet = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, isPublic ? 'TREASURY' : 'WALLET'])).rows[0];
    const destination = (await tx.query<{ id: string }>(`SELECT a.id::TEXT AS id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`)).rows[0];
    const cost = BigInt(blueprint.construction_credit_units);
    if (!wallet || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for construction');
    if (!destination) throw new Error('Construction settlement destination is not configured');
    const requirements = await loadConstructionRequirements(tx, blueprint.id, ownerEconomicId, isPublic);
    const missing = requirements.find((item) => BigInt(item.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for construction; missing ${missing.missing_units}`);
    const resourceAccounts = await Promise.all(requirements.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>(`SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE`, [ownerEconomicId, item.asset_id])).rows[0],
      sink: (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'`, [item.asset_id])).rows[0],
    })));
    if (resourceAccounts.some((item) => !item.account || !item.sink)) throw new Error('Construction resource settlement accounts are not provisioned');
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query(`SELECT earth_post_transaction($1,$2,$3,'ASSET_TRANSFER',$4,$5,'construction-v5',$6::JSONB)`, [input.correlationId, gameDay, Number(currentWorld?.game_minute ?? 0), isPublic ? 'PUBLIC_INFRASTRUCTURE_CONSTRUCTION' : 'PRIVATE_CONSTRUCTION', buildingId, JSON.stringify([{ account_id: wallet.id, delta_units: (-cost).toString(), asset_id: 1 }, { account_id: destination.id, delta_units: cost.toString(), asset_id: 1 }])]);
    if (resourceAccounts.length) await tx.query(`SELECT earth_post_transaction($1,$2,$3,'RESOURCE_CONSUMPTION','SYSTEM_CONSUMPTION',$4,'building-v5',$5::JSONB)`, [`construction:${input.correlationId}:resources`, gameDay, Number(currentWorld?.game_minute ?? 0), buildingId, JSON.stringify(resourceAccounts.flatMap((item) => [{ account_id: item.account!.id, asset_id: item.asset_id, delta_units: (-BigInt(item.required_units)).toString(), reason_code: 'v5_construction_resource_input' }, { account_id: item.sink!.id, asset_id: item.asset_id, delta_units: BigInt(item.required_units).toString(), reason_code: 'v5_construction_resource_input' }]))]);
    await tx.query(`INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, started_game_day, commissioned_game_day, territory_right_id) VALUES ($1,$2,NULL,$3,'UNDER_CONSTRUCTION',$4,NULL,NULL)`, [buildingId, ownerEconomicId, blueprint.id, gameDay]);
    const completionDay = gameDay + Math.max(1, Math.ceil(duration.minutes / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,NULL,$4,$5,$6::JSONB,$7,$8,'IN_PROGRESS',$9,NULL,'V5_POOLED_CONSTRUCTION')`, [`PROJECT-${buildingId.slice(4)}`, buildingId, ownerEconomicId, blueprint.id, cost.toString(), JSON.stringify(Object.fromEntries(requirements.map((item) => [item.code, item.required_units]))), gameDay, completionDay, input.correlationId]);
    if (isPublic) await rebuildV5CorporationSettlementProfile(tx, owner.corporationId!, gameDay);
    else await refreshV5SettlementProfilesForHouse(tx, owner.houseId, gameDay);
    await createGameEvent(tx, { id: `BUILDING-V5-ACQUIRED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_ACQUIRED', gameDay, actorHumanId: input.ownerId, subjectType: 'BUILDING', subjectId: buildingId, title: `${blueprint.code} acquired under pooled Corporation capacity`, details: { buildingId, catalogId: blueprint.id, ownerEconomicId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE', capacityModel: 'V5_POOLED', territoryPlacement: null, effectiveConstructionMinutes: duration.minutes }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', buildingId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE', capacity, project: toJsonSafe((await tx.query('SELECT * FROM construction_projects WHERE id = $1', [`PROJECT-${buildingId.slice(4)}`])).rows[0]), correlationId: input.correlationId };
  });
}
