import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { toJsonSafe } from './json-safe.ts';
import { effectiveConstructionMinutes, loadConstructionRequirements } from './territory-capacity-postgres.ts';
import { quoteV5HouseCapacityChange, quoteV5CorporationCapacityChange } from './v5-capacity-postgres.ts';
import {
  rebuildV5CorporationSettlementProfile,
  refreshV5SettlementProfilesForHouse,
  recordStructuralDelta,
  getHouseSettlementProfileSnapshot,
  getCorporationSettlementProfileSnapshot,
} from './v5-settlement-profiles-postgres.ts';
import { assertScaleCapabilityAuthorized } from './v5-scale-postgres.ts';
import { getAvailableGenerations, assertGenerationAuthorized } from './v5-generation-postgres.ts';
import { readAuthoritativeGameTime, projectDeadline } from './world-clock-postgres.ts';
import { postEconomicTransaction, runEconomicMutation } from './settlement-barrier-postgres.ts';

type Catalog = {
  id: string;
  code: string;
  ownership_scope: 'PRIVATE' | 'PUBLIC';
  construction_credit_units: string;
  construction_minutes: number;
  slot_footprint: number;
  minimum_scale_capability: string;
  technology_domain: string;
};

async function ownerContext(tx: PostgresRepository, humanId: string): Promise<{ houseId: string; houseEconomicId: string; corporationId: string | null; corporationEconomicId: string | null; territoryId: string | null }> {
  const row = (await tx.query<{ house_id: string; house_economic_id: string; corporation_id: string | null; corporation_economic_id: string | null; territory_id: string | null }>(
    `SELECT h.house_id, house_owner.economic_id AS house_economic_id,
            ha.corporation_id, corp_owner.economic_id AS corporation_economic_id,
            COALESCE(ha.primary_territory_id, (SELECT id FROM territories WHERE corporation_id = ha.corporation_id AND status = 'ACTIVE' LIMIT 1)) AS territory_id
       FROM humans h
       JOIN owner_registry house_owner ON house_owner.id = h.house_id AND house_owner.owner_type = 'HOUSE'
       LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
       LEFT JOIN owner_registry corp_owner ON corp_owner.id = ha.corporation_id AND corp_owner.owner_type = 'CORPORATION'
      WHERE h.id = $1 AND h.status = 'ACTIVE' LIMIT 1`, [humanId],
  )).rows[0];
  if (!row) throw new Error('Active House is required for V5 construction');
  return { houseId: row.house_id, houseEconomicId: row.house_economic_id, corporationId: row.corporation_id, corporationEconomicId: row.corporation_economic_id, territoryId: row.territory_id };
}

async function requirePublicCorporationAuthorization(tx: PostgresRepository, corporationId: string, humanId: string): Promise<void> {
  const authorized = (await tx.query(
    `SELECT 1 FROM institution_governance_roles
      WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
        AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER', 'CORPORATION_OPERATOR')`,
    [corporationId, humanId],
  )).rows[0];
  if (!authorized) throw new Error('Public V5 construction requires Corporation governance authorization');
}

async function catalog(tx: PostgresRepository, buildingType: string): Promise<Catalog> {
  const row = (await tx.query<Catalog>(
    `SELECT id, code, ownership_scope, construction_credit_units, construction_minutes, slot_footprint, minimum_scale_capability, technology_domain
       FROM building_catalog
      WHERE (id = $1 OR code = $1 OR lower(code) = lower($1)) AND active = TRUE LIMIT 1`, [buildingType],
  )).rows[0];
  if (!row) throw new Error('Unknown building blueprint');
  return row;
}

export async function quoteV5Building(repository: PostgresRepository, input: { ownerId: string; buildingType: string; generation?: number }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const owner = await ownerContext(tx, input.ownerId);
    const blueprint = await catalog(tx, input.buildingType);
    const isPublic = blueprint.ownership_scope === 'PUBLIC';
    if (isPublic && (!owner.corporationId || !owner.corporationEconomicId)) throw new Error('Public V5 construction requires an active Corporation affiliation');
    if (isPublic) await requirePublicCorporationAuthorization(tx, owner.corporationId!, input.ownerId);
    const ownerEconomicId = isPublic ? owner.corporationEconomicId : owner.houseEconomicId;
    const scaleAuth = await assertScaleCapabilityAuthorized(tx, blueprint.minimum_scale_capability, ownerEconomicId!, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : owner.corporationEconomicId);
    const clock = await readAuthoritativeGameTime(tx);
    const gameDay = clock.gameDay;
    const genInfo = await getAvailableGenerations(tx, blueprint.technology_domain, ownerEconomicId!, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : owner.corporationEconomicId, gameDay);
    const targetGen = input.generation ? Number(input.generation) : genInfo.maxAccessibleGeneration;
    const genAuth = await assertGenerationAuthorized(tx, blueprint.technology_domain, targetGen, ownerEconomicId!, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : owner.corporationEconomicId, gameDay);
    // Quotes are read models but must be total for newly provisioned Houses;
    // materialize the canonical profile before asking the capacity engine.
    if (!isPublic) await refreshV5SettlementProfilesForHouse(tx, owner.houseId, gameDay);
    const delinquency = (await tx.query<{ status: string }>(
      `SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = $1 AND subject_id = $2`,
      [isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? owner.corporationId : owner.houseId],
    )).rows[0]?.status ?? 'CURRENT';
    const blocked = ['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency);
    let capacity: Record<string, unknown> | null;
    try {
      capacity = isPublic
        ? await quoteV5CorporationCapacityChange(tx, owner.corporationId, BigInt(blueprint.slot_footprint), gameDay)
        : await quoteV5HouseCapacityChange(tx, owner.houseId, BigInt(blueprint.slot_footprint), gameDay);
    } catch (error) {
      // A quote must remain inspectable while a newly created authority's
      // daily capacity snapshot is materializing. Construction still enforces
      // the authoritative capacity check in its mutation path.
      capacity = { available: false, reason: error instanceof Error ? error.message : 'V5 capacity quote unavailable' };
    }
    const duration = await effectiveConstructionMinutes(tx, gameDay, null, blueprint.code, blueprint.construction_minutes);
    const requirements = await loadConstructionRequirements(tx, blueprint.id, ownerEconomicId, isPublic);
    const wallet = (await tx.query<{ balance_units: string }>(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = $2 AND status = 'ACTIVE'`,
      [ownerEconomicId, isPublic ? 'TREASURY' : 'WALLET'],
    )).rows[0];
    const insufficientResources = requirements.filter((item) => BigInt(item.missing_units) > 0n).map((item) => ({ code: item.code, missingUnits: item.missing_units }));
    const blockers = [
      ...(!scaleAuth.authorized ? [String(scaleAuth.reason ?? 'Missing required scale capability')] : []),
      ...(!genAuth.authorized ? [String(genAuth.reason ?? 'Missing required technology generation')] : []),
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
      minimumScaleCapability: blueprint.minimum_scale_capability,
      scaleAuthorization: scaleAuth,
      installedGeneration: targetGen,
      maxAccessibleGeneration: genInfo.maxAccessibleGeneration,
      availableGenerations: genInfo.availableGenerations,
      earthFrontierGeneration: genInfo.earthFrontierGeneration,
      technologyDomain: blueprint.technology_domain,
      generationAuthorization: genAuth,
      resourceRequirements: requirements.map((item) => ({ code: item.code, requiredUnits: item.required_units, availableUnits: item.available_units, missingUnits: item.missing_units })),
      effectiveConstructionMinutes: duration.minutes,
      startedAbsoluteGameMinute: clock.totalGameMinutes,
      completionAbsoluteGameMinute: projectDeadline(gameDay, clock.gameMinute, duration.minutes).completionAbsoluteMinute,
      expectedCompletionGameDay: projectDeadline(gameDay, clock.gameMinute, duration.minutes).completionGameDay,
      expectedCompletionGameMinute: projectDeadline(gameDay, clock.gameMinute, duration.minutes).completionGameMinute,
      capacity,
      delinquencyStatus: delinquency,
      generatedFrom: 'postgres-canonical-building-catalog-v5',
    };
  });
}

/** V5 construction command using pooled Corporation capacity, without placement. */
export async function purchaseV5Building(
  repository: PostgresRepository,
  input: {
    ownerId?: string;
    buildingType: string;
    name?: string;
    generation?: number;
    correlationId: string;
    governanceProposalId?: string;
    corporationId?: string;
  },
): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = (await tx.query<{ source_id: string }>('SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior?.source_id) return { ok: true, alreadyProcessed: true, building: toJsonSafe((await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.source_id])).rows[0]), correlationId: input.correlationId };
    const blueprint = await catalog(tx, input.buildingType);
    const isPublic = blueprint.ownership_scope === 'PUBLIC';
    if (isPublic && !input.governanceProposalId) {
      throw new Error('Public Corporation construction requires governance proposal authorization');
    }

    let ownerEconomicId: string;
    let ownerHouseId: string | null = null;
    let ownerCorpId: string | null = null;
    let ownerCorpEconomicId: string | null = null;
    let territoryId: string | null = null;

    if (isPublic) {
      const corpId = input.corporationId ?? (input.ownerId ? (await ownerContext(tx, input.ownerId)).corporationId : null);
      if (!corpId) throw new Error('Public V5 construction requires an active Corporation affiliation');
      const corpEcon = (await tx.query<{ economic_id: string }>("SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = 'CORPORATION'", [corpId])).rows[0]?.economic_id;
      if (!corpEcon) throw new Error('Corporation economic account not found');
      ownerCorpId = corpId;
      ownerCorpEconomicId = corpEcon;
      ownerEconomicId = corpEcon;
      territoryId = (await tx.query<{ id: string }>("SELECT id FROM territories WHERE corporation_id = $1 AND status = 'ACTIVE' ORDER BY is_primary DESC, id ASC LIMIT 1", [corpId])).rows[0]?.id ?? null;
      if (!territoryId) throw new Error('Corporation territory not found for public construction');
    } else {
      if (!input.ownerId) throw new Error('Active Human owner is required for private construction');
      const owner = await ownerContext(tx, input.ownerId);
      ownerHouseId = owner.houseId;
      ownerEconomicId = owner.houseEconomicId;
      ownerCorpId = owner.corporationId;
      ownerCorpEconomicId = owner.corporationEconomicId;
      territoryId = owner.territoryId;
    }

    const scaleAuth = await assertScaleCapabilityAuthorized(tx, blueprint.minimum_scale_capability, ownerEconomicId, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : ownerCorpEconomicId);
    if (!scaleAuth.authorized) throw new Error(String(scaleAuth.reason ?? 'Missing required scale capability'));
    const gameDay = clock.gameDay;
    const genInfo = await getAvailableGenerations(tx, blueprint.technology_domain, ownerEconomicId, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : ownerCorpEconomicId, gameDay);
    const targetGen = input.generation ? Number(input.generation) : genInfo.maxAccessibleGeneration;
    const genAuth = await assertGenerationAuthorized(tx, blueprint.technology_domain, targetGen, ownerEconomicId, isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? null : ownerCorpEconomicId, gameDay);
    if (!genAuth.authorized) throw new Error(String(genAuth.reason ?? 'Missing required technology generation'));
    const delinquency = (await tx.query<{ status: string }>(`SELECT status FROM v5_capacity_delinquency_state WHERE subject_type = $1 AND subject_id = $2`, [isPublic ? 'CORPORATION' : 'HOUSE', isPublic ? ownerCorpId : ownerHouseId])).rows[0];
    if (['EXPANSION_BLOCKED', 'PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_SPENDING_RESTRICTED', 'EARTH_RECEIVERSHIP'].includes(delinquency?.status ?? '')) throw new Error('V5 capacity delinquency blocks construction expansion');
    const capacity = isPublic
      ? await quoteV5CorporationCapacityChange(tx, ownerCorpId!, BigInt(blueprint.slot_footprint), gameDay)
      : await quoteV5HouseCapacityChange(tx, ownerHouseId!, BigInt(blueprint.slot_footprint), gameDay);
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
    const targetGenRow = (await tx.query<{ id: string }>(
      'SELECT id FROM technology_generations WHERE domain_id = $1 AND generation_number = $2 LIMIT 1',
      [genInfo.domainId, targetGen],
    )).rows[0];
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    // Capture before profile snapshot
    const beforeProfile = isPublic
      ? await getCorporationSettlementProfileSnapshot(tx, ownerCorpId!)
      : await getHouseSettlementProfileSnapshot(tx, ownerHouseId!);

    const deadline = projectDeadline(gameDay, clock.gameMinute, duration.minutes);
    await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'ASSET_TRANSFER',
      sourceType: isPublic ? 'PUBLIC_INFRASTRUCTURE_CONSTRUCTION' : 'PRIVATE_CONSTRUCTION',
      sourceId: buildingId,
      rulesVersion: 'construction-v5',
      entries: [
        { account_id: wallet.id, delta_units: (-cost).toString(), asset_id: 1 },
        { account_id: destination.id, delta_units: cost.toString(), asset_id: 1 },
      ],
    }, clock);
    await tx.query(`INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, construction_state, installed_generation, technology_definition_version, started_game_day, commissioned_game_day, territory_right_id) VALUES ($1,$2,$3,$4,'UNDER_CONSTRUCTION','UNDER_CONSTRUCTION',$5,$6,$7,NULL,NULL)`, [buildingId, ownerEconomicId, territoryId, blueprint.id, targetGen, `tech-gen-v${targetGen}`, gameDay]);
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind, target_generation_id) VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,$9,'IN_PROGRESS',$10,NULL,'V5_POOLED_CONSTRUCTION',$11)`, [`PROJECT-${buildingId.slice(4)}`, buildingId, ownerEconomicId, territoryId, blueprint.id, cost.toString(), JSON.stringify(Object.fromEntries(requirements.map((item) => [item.code, item.required_units]))), gameDay, deadline.completionGameDay, input.correlationId, targetGenRow?.id ?? null]);
    if (isPublic) await rebuildV5CorporationSettlementProfile(tx, ownerCorpId!, gameDay);
    else await refreshV5SettlementProfilesForHouse(tx, ownerHouseId!, gameDay);

    // Capture after profile snapshot and record delta
    const afterProfile = isPublic
      ? await getCorporationSettlementProfileSnapshot(tx, ownerCorpId!)
      : await getHouseSettlementProfileSnapshot(tx, ownerHouseId!);

    await recordStructuralDelta(tx, {
      actionType: isPublic ? 'PUBLIC_BUILDING_CHANGE' : 'CONSTRUCTION',
      entityType: isPublic ? 'CORPORATION' : 'HOUSE',
      entityId: isPublic ? ownerCorpId! : ownerHouseId!,
      houseId: isPublic ? null : ownerHouseId,
      corporationId: isPublic ? ownerCorpId! : ownerCorpId,
      buildingId,
      deltaFootprintUnits: BigInt(blueprint.slot_footprint),
      beforeProfileSnapshot: beforeProfile,
      afterProfileSnapshot: afterProfile,
      provenanceSource: input.governanceProposalId ? 'v5_governance_activation' : 'purchaseV5Building',
      provenanceJson: input.governanceProposalId ? { proposalId: input.governanceProposalId, actionType: 'CORPORATION_PUBLIC_CONSTRUCTION' } : null,
      actorHumanId: input.ownerId ?? null,
      correlationId: input.correlationId,
      gameDay,
    });

    await createGameEvent(tx, { id: `BUILDING-V5-ACQUIRED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_ACQUIRED', gameDay, actorHumanId: input.ownerId ?? null, subjectType: 'BUILDING', subjectId: buildingId, title: `${blueprint.code} acquired under pooled Corporation capacity`, details: { buildingId, catalogId: blueprint.id, ownerEconomicId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE', installedGeneration: targetGen, capacityModel: 'V5_POOLED', territoryPlacement: null, effectiveConstructionMinutes: duration.minutes }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', buildingId, ownerType: isPublic ? 'CORPORATION' : 'HOUSE', installedGeneration: targetGen, capacity, project: toJsonSafe((await tx.query('SELECT * FROM construction_projects WHERE id = $1', [`PROJECT-${buildingId.slice(4)}`])).rows[0]), correlationId: input.correlationId };
  });
}

/** Suspend an active building, updating settlement profiles and recording structural delta. */
export async function suspendBuilding(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; correlationId: string; reason?: string },
): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const building = (await tx.query<{
      id: string;
      status: string;
      v5_productive_status: string;
      slot_footprint: number;
      owner_economic_id: string;
      owner_type: 'HOUSE' | 'CORPORATION';
      owner_id: string;
      corporation_id: string | null;
    }>(`
      SELECT b.id, b.status, b.v5_productive_status, bc.slot_footprint,
             b.owner_economic_id, o.owner_type, o.id AS owner_id,
             ha.corporation_id
        FROM buildings b
        JOIN building_catalog bc ON bc.id = b.catalog_id
        JOIN owner_registry o ON o.economic_id = b.owner_economic_id
        LEFT JOIN house_affiliations ha ON ha.house_id = o.id AND ha.status = 'ACTIVE' AND o.owner_type = 'HOUSE'
       WHERE b.id = $1 FOR UPDATE OF b
    `, [input.buildingId])).rows[0];

    if (!building) throw new Error(`Building not found: ${input.buildingId}`);
    if (building.status !== 'ACTIVE' || building.v5_productive_status !== 'ACTIVE') {
      throw new Error(`Only active buildings can be suspended; current status: ${building.status}, productive: ${building.v5_productive_status}`);
    }

    const gameDay = clock.gameDay;

    const beforeProfile = building.owner_type === 'CORPORATION'
      ? await getCorporationSettlementProfileSnapshot(tx, building.owner_id)
      : await getHouseSettlementProfileSnapshot(tx, building.owner_id);

    await tx.query(`
      UPDATE buildings
         SET v5_productive_status = 'SUSPENDED'
       WHERE id = $1
    `, [input.buildingId]);

    if (building.owner_type === 'CORPORATION') {
      await rebuildV5CorporationSettlementProfile(tx, building.owner_id, gameDay);
    } else {
      await refreshV5SettlementProfilesForHouse(tx, building.owner_id, gameDay);
    }

    const afterProfile = building.owner_type === 'CORPORATION'
      ? await getCorporationSettlementProfileSnapshot(tx, building.owner_id)
      : await getHouseSettlementProfileSnapshot(tx, building.owner_id);

    await recordStructuralDelta(tx, {
      actionType: 'BUILDING_SUSPEND',
      entityType: building.owner_type,
      entityId: building.owner_id,
      houseId: building.owner_type === 'HOUSE' ? building.owner_id : null,
      corporationId: building.owner_type === 'CORPORATION' ? building.owner_id : building.corporation_id,
      buildingId: building.id,
      deltaFootprintUnits: -BigInt(building.slot_footprint),
      deltaBuildingCount: -1,
      beforeProfileSnapshot: beforeProfile,
      afterProfileSnapshot: afterProfile,
      provenanceSource: 'suspendBuilding',
      actorHumanId: input.humanId,
      correlationId: input.correlationId,
      gameDay,
    });

    await createGameEvent(tx, {
      id: `BUILDING-SUSPENDED-${input.correlationId}`,
      category: 'BUILDING',
      eventType: 'BUILDING_SUSPENDED',
      gameDay,
      actorHumanId: input.humanId,
      subjectType: 'BUILDING',
      subjectId: building.id,
      title: 'Building suspended',
      details: { buildingId: building.id, reason: input.reason ?? 'manual_suspension' },
      correlationId: input.correlationId,
    });

    return { ok: true, status: 'SUSPENDED', buildingId: building.id, correlationId: input.correlationId };
  });
}

/** Reactivate a suspended building, updating settlement profiles and recording structural delta. */
export async function reactivateBuilding(
  repository: PostgresRepository,
  input: { buildingId: string; humanId: string; correlationId: string },
): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const building = (await tx.query<{
      id: string;
      status: string;
      v5_productive_status: string;
      slot_footprint: number;
      owner_economic_id: string;
      owner_type: 'HOUSE' | 'CORPORATION';
      owner_id: string;
      corporation_id: string | null;
    }>(`
      SELECT b.id, b.status, b.v5_productive_status, bc.slot_footprint,
             b.owner_economic_id, o.owner_type, o.id AS owner_id,
             ha.corporation_id
        FROM buildings b
        JOIN building_catalog bc ON bc.id = b.catalog_id
        JOIN owner_registry o ON o.economic_id = b.owner_economic_id
        LEFT JOIN house_affiliations ha ON ha.house_id = o.id AND ha.status = 'ACTIVE' AND o.owner_type = 'HOUSE'
       WHERE b.id = $1 FOR UPDATE OF b
    `, [input.buildingId])).rows[0];

    if (!building) throw new Error(`Building not found: ${input.buildingId}`);
    if (building.v5_productive_status !== 'SUSPENDED') {
      throw new Error(`Only suspended buildings can be reactivated; current status: ${building.status}, productive: ${building.v5_productive_status}`);
    }

    const gameDay = clock.gameDay;

    const beforeProfile = building.owner_type === 'CORPORATION'
      ? await getCorporationSettlementProfileSnapshot(tx, building.owner_id)
      : await getHouseSettlementProfileSnapshot(tx, building.owner_id);

    await tx.query(`
      UPDATE buildings
         SET v5_productive_status = 'ACTIVE'
       WHERE id = $1
    `, [input.buildingId]);

    if (building.owner_type === 'CORPORATION') {
      await rebuildV5CorporationSettlementProfile(tx, building.owner_id, gameDay);
    } else {
      await refreshV5SettlementProfilesForHouse(tx, building.owner_id, gameDay);
    }

    const afterProfile = building.owner_type === 'CORPORATION'
      ? await getCorporationSettlementProfileSnapshot(tx, building.owner_id)
      : await getHouseSettlementProfileSnapshot(tx, building.owner_id);

    await recordStructuralDelta(tx, {
      actionType: 'BUILDING_REACTIVATE',
      entityType: building.owner_type,
      entityId: building.owner_id,
      houseId: building.owner_type === 'HOUSE' ? building.owner_id : null,
      corporationId: building.owner_type === 'CORPORATION' ? building.owner_id : building.corporation_id,
      buildingId: building.id,
      deltaFootprintUnits: BigInt(building.slot_footprint),
      deltaBuildingCount: 1,
      beforeProfileSnapshot: beforeProfile,
      afterProfileSnapshot: afterProfile,
      provenanceSource: 'reactivateBuilding',
      actorHumanId: input.humanId,
      correlationId: input.correlationId,
      gameDay,
    });

    await createGameEvent(tx, {
      id: `BUILDING-REACTIVATED-${input.correlationId}`,
      category: 'BUILDING',
      eventType: 'BUILDING_REACTIVATED',
      gameDay,
      actorHumanId: input.humanId,
      subjectType: 'BUILDING',
      subjectId: building.id,
      title: 'Building reactivated',
      details: { buildingId: building.id },
      correlationId: input.correlationId,
    });

    return { ok: true, status: 'ACTIVE', buildingId: building.id, correlationId: input.correlationId };
  });
}
