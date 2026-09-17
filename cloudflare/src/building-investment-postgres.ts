import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { quoteV5CorporationCapacityChange, quoteV5HouseCapacityChange } from './v5-capacity-postgres.ts';
import { rebuildV5CorporationSettlementProfile, refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';

async function getHouseBuildingActionContext(repository: PostgresRepository, buildingId: string, humanId: string) {
  const row = (await repository.query<{
    id: string; house_id: string; owner_economic_id: string; tier: number; family_code: string; catalog_id: string;
    slot_footprint: string; construction_credit_units: string; construction_minutes: number;
    operating_mode: string;
  }>(`SELECT b.id, h.house_id, b.owner_economic_id, c.tier, c.family_code, c.id AS catalog_id,
      c.slot_footprint::TEXT, c.construction_credit_units::TEXT, c.construction_minutes,
      b.operating_mode
    FROM buildings b
    JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE'
    JOIN humans h ON h.house_id = o.id AND h.id = $2 AND h.status = 'ACTIVE'
    JOIN building_catalog c ON c.id = b.catalog_id
    WHERE b.id = $1 AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION')
    FOR UPDATE`, [buildingId, humanId])).rows[0];
  if (!row) throw new Error('Building not found or not owned by the active House');
  return row;
}

async function getCorporationBuildingActionContext(repository: PostgresRepository, buildingId: string, humanId: string) {
  const row = (await repository.query<{
    id: string; corporation_id: string; owner_economic_id: string; tier: number; family_code: string;
    slot_footprint: string; construction_credit_units: string; construction_minutes: number; operating_mode: string;
  }>(`SELECT b.id, owner.id AS corporation_id, b.owner_economic_id, c.tier, c.family_code,
      c.slot_footprint::TEXT, c.construction_credit_units::TEXT, c.construction_minutes, b.operating_mode
    FROM buildings b
    JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id AND owner.owner_type = 'CORPORATION'
    JOIN building_catalog c ON c.id = b.catalog_id
    JOIN humans h ON h.id = $2 AND h.status = 'ACTIVE'
    JOIN house_affiliations affiliation ON affiliation.house_id = h.house_id
      AND affiliation.corporation_id = owner.id AND affiliation.status = 'ACTIVE'
    WHERE b.id = $1 AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION')
    FOR UPDATE`, [buildingId, humanId])).rows[0];
  if (!row) throw new Error('Building not found or not owned by the active Corporation');
  const authorized = await repository.query(
    `SELECT 1 FROM institution_governance_roles
      WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
        AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`,
    [row.corporation_id, humanId],
  );
  if (!authorized.rows[0]) throw new Error('Corporation governance authorization is required');
  return row;
}

async function quoteCorporationBuildingUpgrade(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number }>(
      'SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes FROM building_catalog WHERE family_code = $1 AND tier = $2',
      [building.family_code, building.tier + 1])).rows[0];
    const projectInProgress = Boolean((await tx.query('SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0]);
    const footprintDelta = next ? BigInt(next.slot_footprint) - BigInt(building.slot_footprint) : 0n;
    const capacity = await quoteV5CorporationCapacityChange(tx, building.corporation_id, footprintDelta, day);
    const treasury = (await tx.query<{ balance_units: string }>("SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE'", [building.owner_economic_id])).rows[0];
    const creditCost = next ? BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units) : 0n;
    const delinquency = (await tx.query<{ status: string }>("SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1", [building.corporation_id])).rows[0]?.status ?? 'CURRENT';
    const blockers = [
      ...(next ? [] : ['MAX_TIER']),
      ...(projectInProgress ? ['PROJECT_IN_PROGRESS'] : []),
      ...(capacity.available === false && footprintDelta > 0n ? ['CAPACITY_UNAVAILABLE'] : []),
      ...(['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency) ? ['CAPACITY_DELINQUENCY'] : []),
      ...(treasury && BigInt(treasury.balance_units) >= creditCost ? [] : ['INSUFFICIENT_TREASURY']),
    ];
    return {
      ok: true, eligible: blockers.length === 0, buildingId: building.id, ownerType: 'CORPORATION',
      currentTier: building.tier, targetTier: next?.tier ?? null, creditCostUnits: creditCost.toString(),
      footprintDelta: footprintDelta.toString(), constructionMinutes: next?.construction_minutes ?? null,
      effectiveConstructionMinutes: next?.construction_minutes ?? null,
      targetFootprintUnits: next?.slot_footprint ?? null,
      capacity, delinquencyStatus: delinquency, blockers,
      generatedFrom: 'postgres-canonical-corporation-upgrade-quote-v5',
    };
  });
}

async function upgradeCorporationBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, buildingId: prior.source_id, correlationId: input.correlationId };
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    if (building.tier >= 5) throw new Error('Building is already at the maximum tier');
    if ((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]) throw new Error('This building already has an investment project in progress');
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number }>('SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes FROM building_catalog WHERE family_code = $1 AND tier = $2', [building.family_code, building.tier + 1])).rows[0];
    if (!next) throw new Error('Next building tier is unavailable');
    const footprintDelta = BigInt(next.slot_footprint) - BigInt(building.slot_footprint);
    const capacity = await quoteV5CorporationCapacityChange(tx, building.corporation_id, footprintDelta, day);
    if (capacity.available === false) throw new Error(String(capacity.reason ?? 'V5 Corporation capacity quote unavailable'));
    const delinquency = (await tx.query<{ status: string }>("SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1", [building.corporation_id])).rows[0]?.status;
    if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency ?? '')) throw new Error('Corporation capacity delinquency blocks expansion');
    const cost = BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units);
    if (cost < 0n) throw new Error('Building catalog upgrade cost cannot decrease');
    const treasury = (await tx.query<{ id: string; balance_units: string }>("SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id])).rows[0];
    const sink = (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1")).rows[0];
    if (!treasury || !sink || BigInt(treasury.balance_units) < cost) throw new Error('Insufficient Corporation Treasury for tier upgrade');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','PUBLIC_TIER_UPGRADE',$3,'construction-investment-v5',$4::JSONB)`, [input.correlationId, day, input.buildingId, JSON.stringify([{ account_id: treasury.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    const projectId = `PROJECT-UPGRADE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const completion = day + Math.max(1, Math.ceil(Number(next.construction_minutes) / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,NULL,$4,$5,'{}'::JSONB,$6,$7,'IN_PROGRESS',$8,NULL,'TIER_UPGRADE')`, [projectId, building.id, building.owner_economic_id, next.id, cost.toString(), day, completion, input.correlationId]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await rebuildV5CorporationSettlementProfile(tx, building.corporation_id, day);
    await createGameEvent(tx, { id: `BUILDING-UPGRADE-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_TIER_UPGRADE_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `Tier ${building.tier + 1} upgrade started`, details: { projectId, fromTier: building.tier, toTier: building.tier + 1, costUnits: cost.toString(), completionGameDay: completion, ownerType: 'CORPORATION', capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', projectId, ownerType: 'CORPORATION', fromTier: building.tier, toTier: building.tier + 1, creditCostUnits: cost.toString(), expectedCompletionGameDay: completion, v5Capacity: capacity, correlationId: input.correlationId };
  });
}

async function quoteCorporationBuildingDemolition(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    const capacity = await quoteV5CorporationCapacityChange(tx, building.corporation_id, -BigInt(building.slot_footprint), day);
    return { ok: true, eligible: true, buildingId: building.id, ownerType: 'CORPORATION', footprintReleased: building.slot_footprint, capacity, status: 'ACTIVE_OR_UNDER_CONSTRUCTION', generatedFrom: 'postgres-canonical-corporation-demolition-quote-v5' };
  });
}

async function decommissionCorporationBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, buildingId: input.buildingId, status: 'INACTIVE', correlationId: input.correlationId };
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    const capacity = await quoteV5CorporationCapacityChange(tx, building.corporation_id, -BigInt(building.slot_footprint), day);
    const result = await tx.query<{ id: string }>("UPDATE buildings SET status = 'INACTIVE' WHERE id = $1 AND status IN ('ACTIVE','UNDER_CONSTRUCTION') RETURNING id", [input.buildingId]);
    if (!result.rows[0]) throw new Error('Building is already inactive');
    await tx.query("UPDATE construction_projects SET status = 'CANCELLED', cancelled_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId, day]);
    await rebuildV5CorporationSettlementProfile(tx, building.corporation_id, day);
    await createGameEvent(tx, { id: `BUILDING-DECOMMISSIONED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_DECOMMISSIONED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: input.buildingId, title: 'Corporation building decommissioned', details: { buildingId: input.buildingId, ownerType: 'CORPORATION', capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, status: 'INACTIVE', buildingId: input.buildingId, ownerType: 'CORPORATION', v5Capacity: capacity, correlationId: input.correlationId };
  });
}

async function quoteCorporationBuildingOperatingMode(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    return { ok: true, buildingId: building.id, ownerType: 'CORPORATION', currentMode: building.operating_mode, allowedModes: ['CONSERVATIVE', 'BALANCED', 'GROWTH'], generatedFrom: 'postgres-canonical-corporation-policy-contract-v5' };
  });
}

async function setCorporationBuildingOperatingMode(repository: PostgresRepository, input: { buildingId: string; humanId: string; mode: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const building = await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId);
    const result = await tx.query<{ id: string; operating_mode: string }>('UPDATE buildings SET operating_mode = $1 WHERE id = $2 RETURNING id, operating_mode', [input.mode, input.buildingId]);
    await createGameEvent(tx, { id: `BUILDING-POLICY-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_OPERATING_POLICY_CHANGED', gameDay: Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1), actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: 'Corporation building operating policy changed', details: { buildingId: building.id, ownerType: 'CORPORATION', operatingMode: result.rows[0].operating_mode, capacityModel: 'V5_POOLED' }, correlationId: input.correlationId });
    return { ok: true, ownerType: 'CORPORATION', building: result.rows[0], correlationId: input.correlationId };
  });
}

export async function quoteBuildingUpgrade(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type
       FROM buildings b
       JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id
      WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return quoteCorporationBuildingUpgrade(repository, input);
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getHouseBuildingActionContext(tx, input.buildingId, input.humanId);
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number; operating_credit_units: string; resource_input_units: unknown; resource_output_units: unknown; service_capacity_units: string }>(
      'SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes, operating_credit_units::TEXT, resource_input_units, resource_output_units, service_capacity_units::TEXT FROM building_catalog WHERE family_code = $1 AND tier = $2',
      [building.family_code, building.tier + 1])).rows[0];
    const projectInProgress = Boolean((await tx.query('SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0]);
    const footprintDelta = next ? BigInt(next.slot_footprint) - BigInt(building.slot_footprint) : 0n;
    const capacity = await quoteV5HouseCapacityChange(tx, building.house_id, footprintDelta, day);
    const wallet = (await tx.query<{ balance_units: string }>("SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE'", [building.owner_economic_id])).rows[0];
    const creditCost = next ? BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units) : 0n;
    const blockers = [
      ...(next ? [] : ['MAX_TIER']),
      ...(projectInProgress ? ['PROJECT_IN_PROGRESS'] : []),
      ...(capacity.available === false && footprintDelta > 0n ? ['CAPACITY_UNAVAILABLE'] : []),
      ...(wallet && BigInt(wallet.balance_units) >= creditCost ? [] : ['INSUFFICIENT_CREDITS']),
    ];
    return {
      ok: true, eligible: blockers.length === 0, buildingId: building.id,
      currentTier: building.tier, targetTier: next?.tier ?? null,
      creditCostUnits: creditCost.toString(), footprintDelta: footprintDelta.toString(),
      constructionMinutes: next?.construction_minutes ?? null,
      targetCatalog: next ? {
        id: next.id, tier: next.tier, slotFootprint: next.slot_footprint,
        operatingCreditUnits: next.operating_credit_units,
        resourceInputUnits: next.resource_input_units,
        resourceOutputUnits: next.resource_output_units,
        serviceCapacityUnits: next.service_capacity_units,
      } : null,
      capacity, blockers, currentOperatingMode: building.operating_mode,
    };
  });
}

export async function quoteBuildingDemolition(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return quoteCorporationBuildingDemolition(repository, input);
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = await getHouseBuildingActionContext(tx, input.buildingId, input.humanId);
    const capacity = await quoteV5HouseCapacityChange(tx, building.house_id, -BigInt(building.slot_footprint), day);
    return { ok: true, eligible: true, buildingId: building.id, footprintReleased: building.slot_footprint, capacity, status: 'ACTIVE_OR_UNDER_CONSTRUCTION' };
  });
}

export async function upgradeBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type
       FROM buildings b
       JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id
      WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return upgradeCorporationBuilding(repository, input);
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = (await tx.query<{ id: string; owner_economic_id: string; family_code: string; tier: number; catalog_id: string; slot_footprint: string; construction_credit_units: string; construction_minutes: number }>(`SELECT b.id, b.owner_economic_id, c.family_code, c.tier, c.id AS catalog_id, c.slot_footprint::TEXT, c.construction_credit_units::TEXT, c.construction_minutes FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN humans h ON h.id = $2 AND h.house_id = (SELECT id FROM owner_registry WHERE economic_id = b.owner_economic_id AND owner_type = 'HOUSE') AND h.status = 'ACTIVE' WHERE b.id = $1 AND b.status = 'ACTIVE' FOR UPDATE`, [input.buildingId, input.humanId])).rows[0];
    if (!building) throw new Error('Building not found or not owned by the active House');
    if (building.tier >= 5) throw new Error('Building is already at the maximum tier');
    if ((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]) throw new Error('This building already has an investment project in progress');
    const next = (await tx.query<{ id: string; slot_footprint: string; construction_credit_units: string; construction_minutes: number }>('SELECT id, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes FROM building_catalog WHERE family_code = $1 AND tier = $2', [building.family_code, building.tier + 1])).rows[0];
    if (!next) throw new Error('Next building tier is unavailable');
    const houseId = (await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1 AND status = \'ACTIVE\'', [input.humanId])).rows[0]?.house_id;
    const footprintDelta = BigInt(next.slot_footprint) - BigInt(building.slot_footprint);
    const v5CapacityQuote = houseId ? await quoteV5HouseCapacityChange(tx, houseId, footprintDelta, day) : null;
    if (v5CapacityQuote?.available === true && footprintDelta > 0n) {
      const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [houseId])).rows[0];
      if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED'].includes(delinquency?.status ?? '')) throw new Error('House capacity delinquency blocks footprint expansion');
    }
    const cost = BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units);
    const wallet = (await tx.query<{ id: string; balance_units: string }>("SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id])).rows[0];
    const sink = (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1")).rows[0];
    if (!wallet || !sink || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for tier upgrade');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','PRIVATE_TIER_UPGRADE',$3,'construction-investment-v5',$4::JSONB)`, [input.correlationId, day, input.buildingId, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    const projectId = `PROJECT-UPGRADE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const completion = day + Math.max(1, Math.ceil(Number(next.construction_minutes) / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,$4,$5,$6,'{}'::JSONB,$7,$8,'IN_PROGRESS',$9,$10,'TIER_UPGRADE')`, [projectId, building.id, building.owner_economic_id, null, next.id, cost.toString(), day, completion, input.correlationId, null]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await refreshV5SettlementProfilesForHouse(tx, houseId!, day);
    await createGameEvent(tx, { id: `BUILDING-UPGRADE-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_TIER_UPGRADE_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `Tier ${building.tier + 1} upgrade started`, details: { projectId, fromTier: building.tier, toTier: building.tier + 1, costUnits: cost.toString(), completionGameDay: completion, capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', projectId, fromTier: building.tier, toTier: building.tier + 1, creditCostUnits: cost.toString(), expectedCompletionGameDay: completion, v5Capacity: v5CapacityQuote, correlationId: input.correlationId };
  });
}

export async function setBuildingOperatingMode(repository: PostgresRepository, input: { buildingId: string; humanId: string; mode: string; correlationId: string }): Promise<Record<string, unknown>> {
  const mode = input.mode.toUpperCase();
  if (!['CONSERVATIVE', 'BALANCED', 'GROWTH'].includes(mode)) throw new Error('Invalid building operating mode');
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return setCorporationBuildingOperatingMode(repository, { ...input, mode });
  return repository.transaction(async (tx) => {
    const building = await getHouseBuildingActionContext(tx, input.buildingId, input.humanId);
    const result = await tx.query<{ id: string; operating_mode: string }>(
      'UPDATE buildings SET operating_mode = $1 WHERE id = $2 RETURNING id, operating_mode',
      [mode, input.buildingId],
    );
    await createGameEvent(tx, {
      id: `BUILDING-POLICY-${input.correlationId}`,
      category: 'BUILDING',
      eventType: 'BUILDING_OPERATING_POLICY_CHANGED',
      gameDay: Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1),
      actorHumanId: input.humanId,
      subjectType: 'BUILDING',
      subjectId: building.id,
      title: 'House building operating policy changed',
      details: { buildingId: building.id, ownerType: 'HOUSE', operatingMode: result.rows[0].operating_mode, capacityModel: 'V5_POOLED' },
      correlationId: input.correlationId,
    });
    return { ok: true, building: result.rows[0], correlationId: input.correlationId };
  });
}

/** Server-owned operating-policy preview. The client must not infer policy effects. */
export async function quoteBuildingOperatingMode(repository: PostgresRepository, input: { buildingId: string; humanId: string }): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return quoteCorporationBuildingOperatingMode(repository, input);
  const row = (await repository.query<{ id: string; operating_mode: string }>(`SELECT b.id, b.operating_mode
    FROM buildings b
    JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE'
    JOIN humans h ON h.house_id = o.id AND h.id = $2 AND h.status = 'ACTIVE'
    WHERE b.id = $1 AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION')`, [input.buildingId, input.humanId])).rows[0];
  if (!row) throw new Error('Building not found or not owned by the active House');
  return { ok: true, buildingId: row.id, currentMode: row.operating_mode, allowedModes: ['CONSERVATIVE', 'BALANCED', 'GROWTH'], generatedFrom: 'postgres-canonical-policy-contract-v5' };
}

export async function decommissionBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  const owner = (await repository.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
    `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
  )).rows[0];
  if (owner?.owner_type === 'CORPORATION') return decommissionCorporationBuilding(repository, input);
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = (await tx.query<{ id: string; territory_id: string | null; house_id: string; slot_footprint: string }>(`SELECT b.id, b.territory_id, h.house_id, c.slot_footprint::TEXT FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE' JOIN humans h ON h.house_id = o.id AND h.id = $2 AND h.status = 'ACTIVE' JOIN building_catalog c ON c.id = b.catalog_id WHERE b.id = $1 AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION') FOR UPDATE`, [input.buildingId, input.humanId])).rows[0];
    if (!building) throw new Error('Building not found, inactive, or not owned by the active House');
    const v5CapacityQuote = await quoteV5HouseCapacityChange(tx, building.house_id, -BigInt(building.slot_footprint), day);
    const result = await tx.query<{ id: string; territory_id: string }>('UPDATE buildings SET status = \'INACTIVE\' WHERE id = $1 RETURNING id, territory_id', [input.buildingId]);
    await refreshV5SettlementProfilesForHouse(tx, building.house_id, day);
    await tx.query("UPDATE construction_projects SET status = 'CANCELLED', cancelled_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId, day]);
    if (result.rows[0].territory_id) {
      await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [result.rows[0].territory_id, day]);
    }
    await createGameEvent(tx, { id: `BUILDING-DECOMMISSIONED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_DECOMMISSIONED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: input.buildingId, title: 'Building decommissioned', details: { buildingId: input.buildingId }, correlationId: input.correlationId });
    return { ok: true, status: 'INACTIVE', buildingId: input.buildingId, v5Capacity: v5CapacityQuote, correlationId: input.correlationId };
  });
}
