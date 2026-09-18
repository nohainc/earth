import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { quoteV5CorporationCapacityChange, quoteV5HouseCapacityChange } from './v5-capacity-postgres.ts';
import { rebuildV5CorporationSettlementProfile, refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { assertScaleCapabilityAuthorized } from './v5-scale-postgres.ts';
import { getAvailableGenerations, assertGenerationAuthorized } from './v5-generation-postgres.ts';

type UpgradeResourceRequirement = {
  code: string;
  asset_id: number;
  required_units: string;
  available_units: string;
  missing_units: string;
};

/** Compute incremental resource requirements for a tier upgrade (target - current). */
async function loadUpgradeResourceRequirements(
  tx: PostgresRepository,
  currentCatalogId: string,
  targetCatalogId: string,
  ownerEconomicId: string,
): Promise<UpgradeResourceRequirement[]> {
  const rows = (await tx.query<{ code: string; asset_id: number; current_construction: string; target_construction: string; available_units: string }>(
    `SELECT asset.code, asset.id AS asset_id,
            COALESCE(curr.construction_units, 0)::TEXT AS current_construction,
            COALESCE(tgt.construction_units, 0)::TEXT AS target_construction,
            COALESCE(account.balance_units, 0)::TEXT AS available_units
       FROM building_catalog_resource_flows tgt
       JOIN economic_assets asset ON asset.id = tgt.asset_id AND asset.asset_kind = 'RESOURCE'
       LEFT JOIN building_catalog_resource_flows curr ON curr.catalog_id = $1 AND curr.asset_id = tgt.asset_id
       LEFT JOIN economic_accounts account
         ON account.owner_economic_id = $3 AND account.asset_id = tgt.asset_id
        AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE tgt.catalog_id = $2 AND tgt.construction_units > 0
      ORDER BY asset.id`, [currentCatalogId, targetCatalogId, ownerEconomicId],
  )).rows;
  return rows.map((row) => {
    const delta = BigInt(row.target_construction) - BigInt(row.current_construction);
    const required = delta > 0n ? delta : 0n;
    const available = BigInt(row.available_units);
    return {
      code: row.code,
      asset_id: row.asset_id,
      required_units: required.toString(),
      available_units: row.available_units,
      missing_units: (required > available ? required - available : 0n).toString(),
    };
  }).filter((r) => BigInt(r.required_units) > 0n);
}

type RetrofitResourceRequirement = {
  code: string;
  asset_id: number;
  required_units: string;
  available_units: string;
  missing_units: string;
};

/** Compute 40% construction resource requirements for a generation retrofit. */
async function loadRetrofitResourceRequirements(
  tx: PostgresRepository,
  catalogId: string,
  ownerEconomicId: string,
): Promise<RetrofitResourceRequirement[]> {
  const rows = (await tx.query<{ code: string; asset_id: number; construction_units: string; available_units: string }>(
    `SELECT asset.code, asset.id AS asset_id,
            COALESCE(flow.construction_units, 0)::TEXT AS construction_units,
            COALESCE(account.balance_units, 0)::TEXT AS available_units
       FROM building_catalog_resource_flows flow
       JOIN economic_assets asset ON asset.id = flow.asset_id AND asset.asset_kind = 'RESOURCE'
       LEFT JOIN economic_accounts account
         ON account.owner_economic_id = $2 AND account.asset_id = flow.asset_id
        AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
      WHERE flow.catalog_id = $1 AND flow.construction_units > 0
      ORDER BY asset.id`, [catalogId, ownerEconomicId],
  )).rows;
  return rows.map((row) => {
    const raw = BigInt(row.construction_units);
    const scaled = (raw * 4000n) / 10000n;
    const required = raw > 0n && scaled === 0n ? 1n : scaled;
    const available = BigInt(row.available_units);
    return {
      code: row.code,
      asset_id: row.asset_id,
      required_units: required.toString(),
      available_units: row.available_units,
      missing_units: (required > available ? required - available : 0n).toString(),
    };
  }).filter((r) => BigInt(r.required_units) > 0n);
}

async function getHouseBuildingActionContext(repository: PostgresRepository, buildingId: string, humanId: string) {
  const row = (await repository.query<{
    id: string; house_id: string; owner_economic_id: string; tier: number; family_code: string; catalog_id: string;
    slot_footprint: string; construction_credit_units: string; construction_minutes: number;
    operating_mode: string; status: string;
  }>(`SELECT b.id, h.house_id, b.owner_economic_id, c.tier, c.family_code, c.id AS catalog_id,
      c.slot_footprint::TEXT, c.construction_credit_units::TEXT, c.construction_minutes,
      b.operating_mode, b.status
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
    status: string;
  }>(`SELECT b.id, owner.id AS corporation_id, b.owner_economic_id, c.tier, c.family_code,
      c.slot_footprint::TEXT, c.construction_credit_units::TEXT, c.construction_minutes, b.operating_mode,
      b.status
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
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number; minimum_scale_capability: string }>(
      'SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes, minimum_scale_capability FROM building_catalog WHERE family_code = $1 AND tier = $2',
      [building.family_code, building.tier + 1])).rows[0];
    const projectInProgress = Boolean((await tx.query('SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0]);
    const footprintDelta = next ? BigInt(next.slot_footprint) - BigInt(building.slot_footprint) : 0n;
    const capacity = await quoteV5CorporationCapacityChange(tx, building.corporation_id, footprintDelta, day);
    const treasury = (await tx.query<{ balance_units: string }>("SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE'", [building.owner_economic_id])).rows[0];
    const creditCost = next ? BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units) : 0n;
    const delinquency = (await tx.query<{ status: string }>("SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'CORPORATION' AND subject_id = $1", [building.corporation_id])).rows[0]?.status ?? 'CURRENT';
    const scaleAuth = next ? await assertScaleCapabilityAuthorized(tx, next.minimum_scale_capability, building.owner_economic_id, 'CORPORATION') : { authorized: true };
    const resourceRequirements = next ? await loadUpgradeResourceRequirements(tx, building.catalog_id, next.id, building.owner_economic_id) : [];
    const insufficientResources = resourceRequirements.filter((r) => BigInt(r.missing_units) > 0n);
    const blockers = [
      ...(next ? [] : ['MAX_TIER']),
      ...(!scaleAuth.authorized ? ['SCALE_CAPABILITY_REQUIRED'] : []),
      ...(projectInProgress ? ['PROJECT_IN_PROGRESS'] : []),
      ...(capacity.available === false && footprintDelta > 0n ? ['CAPACITY_UNAVAILABLE'] : []),
      ...(['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency) ? ['CAPACITY_DELINQUENCY'] : []),
      ...(insufficientResources.length ? ['INSUFFICIENT_RESOURCES'] : []),
      ...(treasury && BigInt(treasury.balance_units) >= creditCost ? [] : ['INSUFFICIENT_TREASURY']),
    ];
    return {
      ok: true, eligible: blockers.length === 0, buildingId: building.id, ownerType: 'CORPORATION',
      currentTier: building.tier, targetTier: next?.tier ?? null, creditCostUnits: creditCost.toString(),
      footprintDelta: footprintDelta.toString(), constructionMinutes: next?.construction_minutes ?? null,
      effectiveConstructionMinutes: next?.construction_minutes ?? null,
      targetFootprintUnits: next?.slot_footprint ?? null,
      minimumScaleCapability: next?.minimum_scale_capability ?? null,
      scaleAuthorization: scaleAuth,
      resourceRequirements: resourceRequirements.map((r) => ({ code: r.code, requiredUnits: r.required_units, availableUnits: r.available_units, missingUnits: r.missing_units })),
      beforeRentUnits: capacity.currentChargeUnits ?? null,
      afterRentUnits: capacity.afterChargeUnits ?? null,
      deltaRentUnits: capacity.currentChargeUnits != null && capacity.afterChargeUnits != null
        ? (BigInt(capacity.afterChargeUnits) - BigInt(capacity.currentChargeUnits)).toString() : null,
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
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number; minimum_scale_capability: string }>('SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes, minimum_scale_capability FROM building_catalog WHERE family_code = $1 AND tier = $2', [building.family_code, building.tier + 1])).rows[0];
    if (!next) throw new Error('Next building tier is unavailable');
    const scaleAuth = await assertScaleCapabilityAuthorized(tx, next.minimum_scale_capability, building.owner_economic_id, 'CORPORATION');
    if (!scaleAuth.authorized) throw new Error(String(scaleAuth.reason ?? 'Missing required scale capability for tier upgrade'));
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
    // Incremental resource consumption
    const resourceReqs = await loadUpgradeResourceRequirements(tx, building.catalog_id, next.id, building.owner_economic_id);
    const missing = resourceReqs.find((r) => BigInt(r.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for tier upgrade; missing ${missing.missing_units}`);
    const resourceAccounts = await Promise.all(resourceReqs.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>("SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id, item.asset_id])).rows[0],
      resSink: (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'", [item.asset_id])).rows[0],
    })));
    if (resourceAccounts.some((r) => !r.account || !r.resSink)) throw new Error('Upgrade resource settlement accounts are not provisioned');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','PUBLIC_TIER_UPGRADE',$3,'construction-investment-v5',$4::JSONB)`, [input.correlationId, day, input.buildingId, JSON.stringify([{ account_id: treasury.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    if (resourceAccounts.length) await tx.query(`SELECT earth_post_transaction($1,$2,1439,'RESOURCE_CONSUMPTION','SYSTEM_CONSUMPTION',$3,'upgrade-investment-v5',$4::JSONB)`, [`upgrade:${input.correlationId}:resources`, day, input.buildingId, JSON.stringify(resourceAccounts.flatMap((r) => [{ account_id: r.account!.id, asset_id: r.asset_id, delta_units: (-BigInt(r.required_units)).toString(), reason_code: 'v5_upgrade_resource_input' }, { account_id: r.resSink!.id, asset_id: r.asset_id, delta_units: BigInt(r.required_units).toString(), reason_code: 'v5_upgrade_resource_input' }]))]);
    const resourceCostUnits = Object.fromEntries(resourceReqs.map((r) => [r.code, r.required_units]));
    const projectId = `PROJECT-UPGRADE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const completion = day + Math.max(1, Math.ceil(Number(next.construction_minutes) / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,NULL,$4,$5,$6::JSONB,$7,$8,'IN_PROGRESS',$9,NULL,'TIER_UPGRADE')`, [projectId, building.id, building.owner_economic_id, next.id, cost.toString(), JSON.stringify(resourceCostUnits), day, completion, input.correlationId]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await rebuildV5CorporationSettlementProfile(tx, building.corporation_id, day);
    await createGameEvent(tx, { id: `BUILDING-UPGRADE-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_TIER_UPGRADE_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `Tier ${building.tier + 1} upgrade started`, details: { projectId, fromTier: building.tier, toTier: building.tier + 1, costUnits: cost.toString(), resourceCostUnits, completionGameDay: completion, ownerType: 'CORPORATION', capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', projectId, ownerType: 'CORPORATION', fromTier: building.tier, toTier: building.tier + 1, creditCostUnits: cost.toString(), resourceCostUnits, expectedCompletionGameDay: completion, v5Capacity: capacity, correlationId: input.correlationId };
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
    await refreshV5SettlementProfilesForHouse(tx, building.house_id, day);
    const next = (await tx.query<{ id: string; tier: number; slot_footprint: string; construction_credit_units: string; construction_minutes: number; operating_credit_units: string; resource_input_units: unknown; resource_output_units: unknown; service_capacity_units: string; minimum_scale_capability: string }>(
      `SELECT id, tier, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes,
              operating_credit_units::TEXT,
              (SELECT COALESCE(jsonb_object_agg(ea.code, f.operating_input_units), '{}'::JSONB)
                 FROM building_catalog_resource_flows f JOIN economic_assets ea ON ea.id = f.asset_id
                WHERE f.catalog_id = building_catalog.id) AS resource_input_units,
              (SELECT COALESCE(jsonb_object_agg(ea.code, f.operating_output_units), '{}'::JSONB)
                 FROM building_catalog_resource_flows f JOIN economic_assets ea ON ea.id = f.asset_id
                WHERE f.catalog_id = building_catalog.id) AS resource_output_units,
              NULL::BIGINT AS service_capacity_units, minimum_scale_capability
         FROM building_catalog WHERE family_code = $1 AND tier = $2`,
      [building.family_code, building.tier + 1])).rows[0];
    const projectInProgress = Boolean((await tx.query('SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = \'IN_PROGRESS\'', [input.buildingId])).rows[0]);
    const footprintDelta = next ? BigInt(next.slot_footprint) - BigInt(building.slot_footprint) : 0n;
    let capacity: Record<string, unknown>;
    try { capacity = await quoteV5HouseCapacityChange(tx, building.house_id, footprintDelta, day) ?? { available: false, reason: 'V5 capacity quote unavailable' }; }
    catch (error) { capacity = { available: false, reason: error instanceof Error ? error.message : 'V5 capacity quote unavailable' }; }
    const wallet = (await tx.query<{ balance_units: string }>("SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE'", [building.owner_economic_id])).rows[0];
    const creditCost = next ? BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units) : 0n;
    // Scale authorization — look up affiliated corporation for capability access
    const affiliation = (await tx.query<{ corporation_economic_id: string }>(
      `SELECT o.economic_id AS corporation_economic_id FROM house_affiliations ha JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION' WHERE ha.house_id = $1 AND ha.status = 'ACTIVE' LIMIT 1`,
      [building.house_id],
    )).rows[0];
    const scaleAuth = next ? await assertScaleCapabilityAuthorized(tx, next.minimum_scale_capability, building.owner_economic_id, 'HOUSE', affiliation?.corporation_economic_id ?? null) : { authorized: true };
    const resourceRequirements = next ? await loadUpgradeResourceRequirements(tx, building.catalog_id, next.id, building.owner_economic_id) : [];
    const insufficientResources = resourceRequirements.filter((r) => BigInt(r.missing_units) > 0n);
    const blockers = [
      ...(next ? [] : ['MAX_TIER']),
      ...(!scaleAuth.authorized ? ['SCALE_CAPABILITY_REQUIRED'] : []),
      ...(projectInProgress ? ['PROJECT_IN_PROGRESS'] : []),
      ...(capacity.available === false && footprintDelta > 0n ? ['CAPACITY_UNAVAILABLE'] : []),
      ...(insufficientResources.length ? ['INSUFFICIENT_RESOURCES'] : []),
      ...(wallet && BigInt(wallet.balance_units) >= creditCost ? [] : ['INSUFFICIENT_CREDITS']),
    ];
    return {
      ok: true, eligible: blockers.length === 0, buildingId: building.id,
      currentTier: building.tier, targetTier: next?.tier ?? null,
      creditCostUnits: creditCost.toString(), footprintDelta: footprintDelta.toString(),
      constructionMinutes: next?.construction_minutes ?? null,
      minimumScaleCapability: next?.minimum_scale_capability ?? null,
      scaleAuthorization: scaleAuth,
      resourceRequirements: resourceRequirements.map((r) => ({ code: r.code, requiredUnits: r.required_units, availableUnits: r.available_units, missingUnits: r.missing_units })),
      beforeRentUnits: capacity.currentChargeUnits ?? null,
      afterRentUnits: capacity.afterChargeUnits ?? null,
      deltaRentUnits: capacity.currentChargeUnits != null && capacity.afterChargeUnits != null
        ? (BigInt(capacity.afterChargeUnits) - BigInt(capacity.currentChargeUnits)).toString() : null,
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
    await refreshV5SettlementProfilesForHouse(tx, (await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1', [input.humanId])).rows[0].house_id, day);
    if (building.tier >= 5) throw new Error('Building is already at the maximum tier');
    if ((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]) throw new Error('This building already has an investment project in progress');
    const next = (await tx.query<{ id: string; slot_footprint: string; construction_credit_units: string; construction_minutes: number; minimum_scale_capability: string }>('SELECT id, slot_footprint::TEXT, construction_credit_units::TEXT, construction_minutes, minimum_scale_capability FROM building_catalog WHERE family_code = $1 AND tier = $2', [building.family_code, building.tier + 1])).rows[0];
    if (!next) throw new Error('Next building tier is unavailable');
    // Scale authorization
    const houseId = (await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1 AND status = \'ACTIVE\'', [input.humanId])).rows[0]?.house_id;
    const affiliation = houseId ? (await tx.query<{ corporation_economic_id: string }>(
      `SELECT o.economic_id AS corporation_economic_id FROM house_affiliations ha JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION' WHERE ha.house_id = $1 AND ha.status = 'ACTIVE' LIMIT 1`,
      [houseId],
    )).rows[0] : null;
    const scaleAuth = await assertScaleCapabilityAuthorized(tx, next.minimum_scale_capability, building.owner_economic_id, 'HOUSE', affiliation?.corporation_economic_id ?? null);
    if (!scaleAuth.authorized) throw new Error(String(scaleAuth.reason ?? 'Missing required scale capability for tier upgrade'));
    const footprintDelta = BigInt(next.slot_footprint) - BigInt(building.slot_footprint);
    let v5CapacityQuote: Record<string, unknown> | null = null;
    if (houseId) {
      try { v5CapacityQuote = await quoteV5HouseCapacityChange(tx, houseId, footprintDelta, day); }
      catch (error) { v5CapacityQuote = { available: false, reason: error instanceof Error ? error.message : 'V5 capacity quote unavailable' }; }
    }
    if (v5CapacityQuote?.available === true && footprintDelta > 0n) {
      const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [houseId])).rows[0];
      if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED'].includes(delinquency?.status ?? '')) throw new Error('House capacity delinquency blocks footprint expansion');
    }
    const cost = BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units);
    const wallet = (await tx.query<{ id: string; balance_units: string }>("SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id])).rows[0];
    const sink = (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1")).rows[0];
    if (!wallet || !sink || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for tier upgrade');
    // Incremental resource consumption
    const resourceReqs = await loadUpgradeResourceRequirements(tx, building.catalog_id, next.id, building.owner_economic_id);
    const missing = resourceReqs.find((r) => BigInt(r.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for tier upgrade; missing ${missing.missing_units}`);
    const resourceAccounts = await Promise.all(resourceReqs.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>("SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id, item.asset_id])).rows[0],
      resSink: (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'", [item.asset_id])).rows[0],
    })));
    if (resourceAccounts.some((r) => !r.account || !r.resSink)) throw new Error('Upgrade resource settlement accounts are not provisioned');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','PRIVATE_TIER_UPGRADE',$3,'construction-investment-v5',$4::JSONB)`, [input.correlationId, day, input.buildingId, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    if (resourceAccounts.length) await tx.query(`SELECT earth_post_transaction($1,$2,1439,'RESOURCE_CONSUMPTION','SYSTEM_CONSUMPTION',$3,'upgrade-investment-v5',$4::JSONB)`, [`upgrade:${input.correlationId}:resources`, day, input.buildingId, JSON.stringify(resourceAccounts.flatMap((r) => [{ account_id: r.account!.id, asset_id: r.asset_id, delta_units: (-BigInt(r.required_units)).toString(), reason_code: 'v5_upgrade_resource_input' }, { account_id: r.resSink!.id, asset_id: r.asset_id, delta_units: BigInt(r.required_units).toString(), reason_code: 'v5_upgrade_resource_input' }]))]);
    const resourceCostUnits = Object.fromEntries(resourceReqs.map((r) => [r.code, r.required_units]));
    const projectId = `PROJECT-UPGRADE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const completion = day + Math.max(1, Math.ceil(Number(next.construction_minutes) / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,$9,'IN_PROGRESS',$10,$11,'TIER_UPGRADE')`, [projectId, building.id, building.owner_economic_id, null, next.id, cost.toString(), JSON.stringify(resourceCostUnits), day, completion, input.correlationId, null]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await refreshV5SettlementProfilesForHouse(tx, houseId!, day);
    await createGameEvent(tx, { id: `BUILDING-UPGRADE-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_TIER_UPGRADE_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `Tier ${building.tier + 1} upgrade started`, details: { projectId, fromTier: building.tier, toTier: building.tier + 1, costUnits: cost.toString(), resourceCostUnits, completionGameDay: completion, capacityModel: 'V5_POOLED', territoryPlacement: null }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', projectId, fromTier: building.tier, toTier: building.tier + 1, creditCostUnits: cost.toString(), resourceCostUnits, expectedCompletionGameDay: completion, v5Capacity: v5CapacityQuote, correlationId: input.correlationId };
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

export async function quoteBuildingRetrofit(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; targetGeneration?: number },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const owner = (await tx.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
      `SELECT owner.owner_type
         FROM buildings b
         JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id
        WHERE b.id = $1`, [input.buildingId],
    )).rows[0];
    if (!owner) throw new Error('Building not found');

    const isPublic = owner.owner_type === 'CORPORATION';
    const building = isPublic
      ? await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId)
      : await getHouseBuildingActionContext(tx, input.buildingId, input.humanId);

    const bldDetails = (await tx.query<{ installed_generation: number; construction_state: string; technology_domain: string }>(
      `SELECT b.installed_generation, b.construction_state, c.technology_domain
         FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id
        WHERE b.id = $1`, [input.buildingId],
    )).rows[0];

    const currentGen = Number(bldDetails?.installed_generation ?? 1);
    const domain = bldDetails?.technology_domain ?? 'ENERGY';

    const affiliation = isPublic ? null : (await tx.query<{ corporation_economic_id: string }>(
      `SELECT o.economic_id AS corporation_economic_id FROM house_affiliations ha JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION' WHERE ha.house_id = $1 AND ha.status = 'ACTIVE' LIMIT 1`,
      [(building as any).house_id],
    )).rows[0];

    const genInfo = await getAvailableGenerations(
      tx, domain, building.owner_economic_id, isPublic ? 'CORPORATION' : 'HOUSE',
      isPublic ? null : affiliation?.corporation_economic_id ?? null, day,
    );

    const targetGen = input.targetGeneration ? Number(input.targetGeneration) : (currentGen + 1);
    const genAuth = await assertGenerationAuthorized(
      tx, domain, targetGen, building.owner_economic_id, isPublic ? 'CORPORATION' : 'HOUSE',
      isPublic ? null : affiliation?.corporation_economic_id ?? null, day,
    );

    const projectInProgress = Boolean((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]);
    const creditCost = (BigInt(building.construction_credit_units) * 4000n) / 10000n;
    const accountType = isPublic ? 'TREASURY' : 'WALLET';
    const accountRow = (await tx.query<{ balance_units: string }>(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE'`,
      [building.owner_economic_id, accountType],
    )).rows[0];

    if (isPublic) {
      await rebuildV5CorporationSettlementProfile(tx, (building as any).corporation_id, day);
    } else {
      await refreshV5SettlementProfilesForHouse(tx, (building as any).house_id, day);
    }

    const resourceReqs = await loadRetrofitResourceRequirements(tx, building.catalog_id, building.owner_economic_id);
    const insufficientResources = resourceReqs.filter((r) => BigInt(r.missing_units) > 0n);

    let capacity: Record<string, unknown>;
    try {
      capacity = isPublic
        ? (await quoteV5CorporationCapacityChange(tx, (building as any).corporation_id, 0n, day)) ?? { available: false, reason: 'V5 capacity quote unavailable' }
        : (await quoteV5HouseCapacityChange(tx, (building as any).house_id, 0n, day)) ?? { available: false, reason: 'V5 capacity quote unavailable' };
    } catch (error) {
      capacity = { available: false, reason: error instanceof Error ? error.message : 'V5 capacity quote unavailable' };
    }

    const blockers = [
      ...(targetGen <= currentGen ? ['TARGET_GENERATION_NOT_GREATER'] : []),
      ...(!genAuth.authorized ? [String(genAuth.reason ?? 'GENERATION_UNAVAILABLE')] : []),
      ...(projectInProgress ? ['PROJECT_IN_PROGRESS'] : []),
      ...(building.status !== 'ACTIVE' ? ['BUILDING_NOT_ACTIVE'] : []),
      ...(insufficientResources.length ? ['INSUFFICIENT_RESOURCES'] : []),
      ...(accountRow && BigInt(accountRow.balance_units) >= creditCost ? [] : [isPublic ? 'INSUFFICIENT_TREASURY' : 'INSUFFICIENT_CREDITS']),
    ];

    const durationMinutes = Math.max(1440, Math.ceil(Number(building.construction_minutes) * 0.4));
    const completionDay = day + Math.max(1, Math.ceil(durationMinutes / 1440));

    return {
      ok: true,
      eligible: blockers.length === 0,
      buildingId: building.id,
      ownerType: isPublic ? 'CORPORATION' : 'HOUSE',
      currentGeneration: currentGen,
      targetGeneration: targetGen,
      earthFrontierGeneration: genInfo.earthFrontierGeneration,
      availableGenerations: genInfo.availableGenerations,
      technologyDomain: domain,
      generationAuthorization: genAuth,
      creditCostUnits: creditCost.toString(),
      resourceRequirements: resourceReqs.map((r) => ({ code: r.code, requiredUnits: r.required_units, availableUnits: r.available_units, missingUnits: r.missing_units })),
      footprintDelta: '0',
      beforeRentUnits: capacity?.currentChargeUnits ?? null,
      afterRentUnits: capacity?.afterChargeUnits ?? null,
      deltaRentUnits: '0',
      constructionMinutes: durationMinutes,
      effectiveConstructionMinutes: durationMinutes,
      expectedCompletionGameDay: completionDay,
      capacity,
      blockers,
      generatedFrom: 'postgres-canonical-retrofit-quote-v5',
    };
  });
}

export async function retrofitBuilding(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; targetGeneration?: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, buildingId: prior.source_id, correlationId: input.correlationId };

    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const owner = (await tx.query<{ owner_type: 'HOUSE' | 'CORPORATION' }>(
      `SELECT owner.owner_type FROM buildings b JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id WHERE b.id = $1`, [input.buildingId],
    )).rows[0];
    if (!owner) throw new Error('Building not found');

    const isPublic = owner.owner_type === 'CORPORATION';
    const building = isPublic
      ? await getCorporationBuildingActionContext(tx, input.buildingId, input.humanId)
      : await getHouseBuildingActionContext(tx, input.buildingId, input.humanId);

    if (building.status !== 'ACTIVE') throw new Error('Only an active building can be retrofitted');
    if ((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]) {
      throw new Error('This building already has an investment project in progress');
    }

    const bldDetails = (await tx.query<{ installed_generation: number; technology_domain: string }>(
      `SELECT b.installed_generation, c.technology_domain
         FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id
        WHERE b.id = $1`, [input.buildingId],
    )).rows[0];
    const currentGen = Number(bldDetails?.installed_generation ?? 1);
    const domain = bldDetails?.technology_domain ?? 'ENERGY';

    const affiliation = isPublic ? null : (await tx.query<{ corporation_economic_id: string }>(
      `SELECT o.economic_id AS corporation_economic_id FROM house_affiliations ha JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION' WHERE ha.house_id = $1 AND ha.status = 'ACTIVE' LIMIT 1`,
      [(building as any).house_id],
    )).rows[0];

    const genInfo = await getAvailableGenerations(
      tx, domain, building.owner_economic_id, isPublic ? 'CORPORATION' : 'HOUSE',
      isPublic ? null : affiliation?.corporation_economic_id ?? null, day,
    );

    const targetGen = input.targetGeneration ? Number(input.targetGeneration) : (currentGen + 1);
    if (targetGen <= currentGen) throw new Error(`Target generation (${targetGen}) must be greater than current installed generation (${currentGen})`);

    const genAuth = await assertGenerationAuthorized(
      tx, domain, targetGen, building.owner_economic_id, isPublic ? 'CORPORATION' : 'HOUSE',
      isPublic ? null : affiliation?.corporation_economic_id ?? null, day,
    );
    if (!genAuth.authorized) throw new Error(String(genAuth.reason ?? 'Missing required technology generation for retrofit'));

    const targetGenRow = (await tx.query<{ id: string }>(
      'SELECT id FROM technology_generations WHERE domain_id = $1 AND generation_number = $2 LIMIT 1',
      [genInfo.domainId, targetGen],
    )).rows[0];

    const cost = (BigInt(building.construction_credit_units) * 4000n) / 10000n;
    const accountType = isPublic ? 'TREASURY' : 'WALLET';
    const payerAccount = (await tx.query<{ id: string; balance_units: string }>(
      `SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE' FOR UPDATE`,
      [building.owner_economic_id, accountType],
    )).rows[0];
    const sink = (await tx.query<{ id: string }>(
      `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1`,
    )).rows[0];
    if (!payerAccount || !sink || BigInt(payerAccount.balance_units) < cost) {
      throw new Error(`Insufficient ${accountType === 'TREASURY' ? 'Corporation Treasury' : 'Credits'} for retrofit`);
    }

    // Incremental resource consumption (MATERIAL, COMPONENTS, COMPUTE)
    const resourceReqs = await loadRetrofitResourceRequirements(tx, building.catalog_id, building.owner_economic_id);
    const missing = resourceReqs.find((r) => BigInt(r.missing_units) > 0n);
    if (missing) throw new Error(`Insufficient ${missing.code} for retrofit; missing ${missing.missing_units}`);

    const resourceAccounts = await Promise.all(resourceReqs.map(async (item) => ({
      ...item,
      account: (await tx.query<{ id: string }>(
        `SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE`,
        [building.owner_economic_id, item.asset_id],
      )).rows[0],
      resSink: (await tx.query<{ id: string }>(
        `SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-RESOURCE-CONSUMPTION' AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'`,
        [item.asset_id],
      )).rows[0],
    })));
    if (resourceAccounts.some((r) => !r.account || !r.resSink)) throw new Error('Retrofit resource settlement accounts are not provisioned');

    // Post CREDIT transfer
    await tx.query(
      `SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER',$3,$4,'retrofit-investment-v5',$5::JSONB)`,
      [input.correlationId, day, isPublic ? 'PUBLIC_RETROFIT' : 'PRIVATE_RETROFIT', input.buildingId, JSON.stringify([
        { account_id: payerAccount.id, asset_id: 1, delta_units: (-cost).toString() },
        { account_id: sink.id, asset_id: 1, delta_units: cost.toString() },
      ])],
    );

    // Post RESOURCE CONSUMPTION transfer
    if (resourceAccounts.length) {
      await tx.query(
        `SELECT earth_post_transaction($1,$2,1439,'RESOURCE_CONSUMPTION','SYSTEM_CONSUMPTION',$3,'retrofit-investment-v5',$4::JSONB)`,
        [`retrofit:${input.correlationId}:resources`, day, input.buildingId, JSON.stringify(resourceAccounts.flatMap((r) => [
          { account_id: r.account!.id, asset_id: r.asset_id, delta_units: (-BigInt(r.required_units)).toString(), reason_code: 'v5_retrofit_resource_input' },
          { account_id: r.resSink!.id, asset_id: r.asset_id, delta_units: BigInt(r.required_units).toString(), reason_code: 'v5_retrofit_resource_input' },
        ]))],
      );
    }

    const resourceCostUnits = Object.fromEntries(resourceReqs.map((r) => [r.code, r.required_units]));
    const projectId = `PROJECT-RETROFIT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const durationMinutes = Math.max(1440, Math.ceil(Number(building.construction_minutes) * 0.4));
    const completion = day + Math.max(1, Math.ceil(durationMinutes / 1440));

    await tx.query(
      `INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind, target_generation_id) VALUES ($1,$2,$3,NULL,$4,$5,$6::JSONB,$7,$8,'IN_PROGRESS',$9,NULL,'GENERATION_RETROFIT',$10)`,
      [projectId, building.id, building.owner_economic_id, building.catalog_id, cost.toString(), JSON.stringify(resourceCostUnits), day, completion, input.correlationId, targetGenRow?.id ?? null],
    );

    // Set downtime and RETROFITTING state
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION', construction_state = 'RETROFITTING' WHERE id = $1", [building.id]);

    // Update settlement profiles transactionally
    if (isPublic) {
      await rebuildV5CorporationSettlementProfile(tx, (building as any).corporation_id, day);
    } else {
      await refreshV5SettlementProfilesForHouse(tx, (building as any).house_id, day);
    }

    await createGameEvent(tx, {
      id: `BUILDING-RETROFIT-${input.correlationId}`,
      category: 'BUILDING',
      eventType: 'BUILDING_RETROFIT_STARTED',
      gameDay: day,
      actorHumanId: input.humanId,
      subjectType: 'BUILDING',
      subjectId: building.id,
      title: `Generation ${targetGen} retrofit started`,
      details: {
        projectId,
        fromGeneration: currentGen,
        toGeneration: targetGen,
        costUnits: cost.toString(),
        resourceCostUnits,
        completionGameDay: completion,
        ownerType: isPublic ? 'CORPORATION' : 'HOUSE',
        capacityModel: 'V5_POOLED',
      },
      correlationId: input.correlationId,
    });

    return {
      ok: true,
      status: 'UNDER_CONSTRUCTION',
      constructionState: 'RETROFITTING',
      projectId,
      ownerType: isPublic ? 'CORPORATION' : 'HOUSE',
      fromGeneration: currentGen,
      toGeneration: targetGen,
      creditCostUnits: cost.toString(),
      resourceCostUnits,
      expectedCompletionGameDay: completion,
      correlationId: input.correlationId,
    };
  });
}
