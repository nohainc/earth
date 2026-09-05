import type { PostgresRepository } from './repository.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';
import { transferCredits } from './financial-postgres.ts';
import { mutateResourceBalance } from './resource-ledger-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import {
  BUILDING_CATALOG,
  type OperatingPolicy,
  type OwnershipClass,
} from './real-estate-catalog.ts';
export interface DistrictZoningSummary {
  cityId: string;
  cityName: string;
  population: number;
  districtModulesCount: number;
  maxCitizens: number;
  totalSlots: number;
  civicReservedSlots: number;
  usedPrivateSlots: number;
  usedCivicSlots: number;
  availablePrivateSlots: number;
  availableCivicSlots: number;
  buildingsCount: number;
  personalEstateTier?: number;
  personalMaxSlots?: number;
  personalUsedSlots?: number;
  personalAvailableSlots?: number;
}

/**
 * Calculates authoritative 2D Horizontal City District Modules & 3D Vertical Private capacity.
 * - Each Urban District Module grants +10 Max Citizens, +100 Private Slots, +20 Civic Slots (120 total).
 * - Each citizen has a personal Private Estate Plot (Tier 1 = 10 slots, Tier 2 = 20 slots, etc.).
 */
export async function getCityDistrictZoning(
  repository: PostgresRepository,
  cityId: string,
  viewerId?: string,
): Promise<DistrictZoningSummary> {
  const cityRes = await repository.query<{ id: string; name: string }>(
    `SELECT cities.id, institutions.name
       FROM cities
       JOIN institutions ON institutions.id = cities.institution_id
      WHERE cities.id = $1`,
    [cityId],
  );
  const city = cityRes.rows[0];
  const cityName = city?.name ?? 'Metropolitan District';

  const popRes = await repository.query<{ count: string }>(
    'SELECT COUNT(*)::integer AS count FROM memberships WHERE city_id = $1',
    [cityId],
  );
  const population = Number(popRes.rows[0]?.count ?? 1);

  // Count active Urban District Modules in the city (minimum 1 founding district guaranteed)
  const distRes = await repository.query<{ count: string }>(
    "SELECT COUNT(*)::integer AS count FROM buildings WHERE city_id = $1 AND building_type = 'urban-district-module' AND status NOT IN ('closed', 'foreclosed')",
    [cityId],
  );
  const districtModulesCount = Math.max(1, Number(distRes.rows[0]?.count || 1));

  const maxCitizens = districtModulesCount * 10;
  const totalSlots = districtModulesCount * 120;
  const civicReservedSlots = districtModulesCount * 20;

  const bldRes = await repository.query<{
    id: string;
    owner_id: string;
    building_type: string;
    tier: number;
    slot_footprint: number;
    ownership_class: string;
  }>(
    "SELECT id, owner_id, building_type, tier, slot_footprint, ownership_class FROM buildings WHERE city_id = $1 AND status NOT IN ('closed', 'foreclosed')",
    [cityId],
  );
  const personalEstateRes = viewerId
    ? await repository.query<{ tier: number }>(
        "SELECT COALESCE(MAX(tier), 1)::integer AS tier FROM buildings WHERE owner_id = $1 AND building_type = 'private-estate-plot' AND status NOT IN ('closed', 'foreclosed')",
        [viewerId],
      )
    : { rows: [] as Array<{ tier: number }> };

  let usedPrivateSlots = 0;
  let usedCivicSlots = 0;
  let personalEstateTier = Math.max(1, Number(personalEstateRes.rows[0]?.tier ?? 1));
  let personalUsedSlots = 0;

  for (const row of bldRes.rows) {
    const footprint = Math.max(0, Number(row.slot_footprint || 0));
    const oClass = (row.ownership_class || 'private').toLowerCase();
    if (oClass === 'private') {
      usedPrivateSlots += footprint;
      if (viewerId && row.owner_id === viewerId) {
        personalUsedSlots += footprint;
      }
    } else {
      usedCivicSlots += footprint;
    }
  }

  const maxPrivatePermitted = Math.max(0, totalSlots - civicReservedSlots);
  const availablePrivateSlots = Math.max(0, maxPrivatePermitted - usedPrivateSlots);
  const availableCivicSlots = Math.max(0, totalSlots - usedCivicSlots - usedPrivateSlots);

  const personalMaxSlots = personalEstateTier * 10;
  const personalAvailableSlots = Math.max(0, personalMaxSlots - personalUsedSlots);

  return {
    cityId,
    cityName,
    population,
    districtModulesCount,
    maxCitizens,
    totalSlots,
    civicReservedSlots,
    usedPrivateSlots,
    usedCivicSlots,
    availablePrivateSlots,
    availableCivicSlots,
    buildingsCount: bldRes.rows.length,
    personalEstateTier,
    personalMaxSlots,
    personalUsedSlots,
    personalAvailableSlots,
  };
}

export async function purchasePrivatePlotAndConstruct(
  repository: PostgresRepository,
  input: {
    ownerId: string;
    cityId: string;
    buildingType: string;
    name: string;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'building_purchase' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const existing = await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.rows[0].reason_id]);
      return { ok: true, alreadyProcessed: true, building: existing.rows[0], correlationId: input.correlationId };
    }

    const catalogRow = (await tx.query<any>(
      `SELECT id, building_type, name, tier, ownership_class, slot_footprint,
              cost_credits, cost_materials, output_credits, output_energy, output_food,
              output_materials, output_components, output_compute, upkeep_energy,
              upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, operating_credits
         FROM building_catalog WHERE id = $1 AND tier = 1 AND is_active = true`,
      [`${input.buildingType}-t1`],
    )).rows[0];
    if (!catalogRow) throw new Error('Unknown or inactive building blueprint');
    const spec = {
      type: catalogRow.building_type,
      name: catalogRow.name,
      tier: Number(catalogRow.tier),
      defaultOwnershipClass: catalogRow.ownership_class,
      slotFootprint: Number(catalogRow.slot_footprint),
      baseCreditCost: Number(catalogRow.cost_credits ?? 0),
      baseMaterialCost: Number(catalogRow.cost_materials ?? 0),
      dailyEnergyUpkeep: Number(catalogRow.upkeep_energy ?? 0),
      dailyFoodUpkeep: Number(catalogRow.upkeep_food ?? 0),
      dailyMaterialsUpkeep: Number(catalogRow.upkeep_materials ?? 0),
      dailyComponentsUpkeep: Number(catalogRow.upkeep_components ?? 0),
      dailyComputeUpkeep: Number(catalogRow.upkeep_compute ?? 0),
      dailyStaffingCredits: Number(catalogRow.operating_credits ?? 0),
      resourceOutputType: catalogRow.output_credits > 0 ? 'credits' : catalogRow.output_energy > 0 ? 'energy' : catalogRow.output_food > 0 ? 'food' : catalogRow.output_materials > 0 ? 'material' : catalogRow.output_components > 0 ? 'components' : 'compute',
      resourceOutputAmount: Number(catalogRow.output_credits || catalogRow.output_energy || catalogRow.output_food || catalogRow.output_materials || catalogRow.output_components || catalogRow.output_compute || 0),
    };
    if (spec.defaultOwnershipClass === 'civic') {
      throw new Error('Civic utility buildings must be procured via Democratic City Referendum');
    }

    const membership = await tx.query<{ city_id: string | null; corporation_id: string | null }>(
      'SELECT city_id, corporation_id FROM memberships WHERE human_id = $1',
      [input.ownerId],
    );
    const isPrivateEstate = input.buildingType === 'private-estate-plot';
    const citizenCityId = isPrivateEstate
      ? null
      : (membership.rows[0]?.city_id ?? input.cityId);

    // Check District Zoning Capacity (both city-wide and personal estate vertical quota)
    const zoning = citizenCityId
      ? await getCityDistrictZoning(tx, citizenCityId, input.ownerId)
      : null;
    if (zoning && zoning.availablePrivateSlots < spec.slotFootprint) {
      throw new Error(
        `City district capacity exceeded. This building requires ${spec.slotFootprint} slots, but only ${zoning.availablePrivateSlots} private slots are available in ${zoning.cityName}.`,
      );
    }
    if (zoning && spec.slotFootprint > 0 && (zoning.personalAvailableSlots ?? 10) < spec.slotFootprint) {
      throw new Error(
        `Personal estate capacity exceeded. This building requires ${spec.slotFootprint} slots, but you only have ${zoning.personalAvailableSlots ?? 0} slots remaining on your current Estate Deck (Tier ${zoning.personalEstateTier ?? 1}). Upgrade your Estate to unlock more vertical space.`,
      );
    }

    // Check Credits
    const creditCostCents = BigInt(Math.round(spec.baseCreditCost * 100));
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.ownerId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Insufficient Credits for plot and construction (Requires ${spec.baseCreditCost} CRD)`);
    }

    // Check Materials
    const materialCost = spec.baseMaterialCost;
    const world = await tx.query<{ genesis_at: string; simulated_day_offset: number }>(
      "SELECT genesis_at, simulated_day_offset FROM world_state WHERE id = 'WORLD'",
    );
    const authTime = getAuthoritativeGameTime({
      genesisAt: world.rows[0]?.genesis_at,
      simulatedDayOffset: world.rows[0]?.simulated_day_offset,
    });
    const day = authTime.gameDay;
    const currentTotalMinute = authTime.totalGameMinutes;
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    // Transfer Credits (60% to City Treasury, 25% to Corp Treasury if affiliated, 15% to OUC)
    const costMoney = centsToMoney(creditCostCents);
    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: isPrivateEstate
        ? 'account-ouc-treasury'
        : `account-city-${citizenCityId}`,
      amount: costMoney,
      reasonType: 'building_purchase',
      reasonId: buildingId,
      ruleVersion: 'real-estate-v2',
      correlationId: input.correlationId,
    });

    // Deduct Materials with guaranteed ledger audit
    if (materialCost > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.ownerId,
        resource: 'material',
        delta: -materialCost,
        reasonType: 'building_construction',
        reasonId: buildingId,
        correlationId: `${input.correlationId}:material`,
        gameDay: day,
      });
    }

    // Calculate construction timeline from catalog or spec in minutes
    const catalogRes = await tx.query<{ construction_days: number; construction_minutes: number }>(
      'SELECT construction_days, construction_minutes FROM building_catalog WHERE id = $1',
      [`${input.buildingType}-t${spec.tier || 1}`],
    );
    const constructionMinutes = Math.max(
      1,
      catalogRes.rows[0]?.construction_minutes ??
        ((catalogRes.rows[0]?.construction_days ?? spec.slotFootprint ?? 1) * 1440),
    );
    const completeMinute = currentTotalMinute + constructionMinutes;
    // game_day is a display/settlement bucket (day 1 starts at minute 0),
    // while the minute columns are the authoritative construction timeline.
    const completeDay = Math.floor(completeMinute / 1440) + 1;

    const catalogId = `${input.buildingType}-t${spec.tier || 1}`;

    // Insert Building with authoritative catalog_id and minute timestamps
    await tx.query(
      `INSERT INTO buildings (
        id, city_id, owner_id, ownership_class,
        catalog_id, building_type, name, tier, condition, slot_footprint,
        operating_policy, auto_repair_enabled,
        upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
        daily_operating_credits,
        resource_output_type, resource_output_amount,
        construction_started_game_day, construction_complete_game_day,
        construction_started_minute, construction_complete_minute,
        construction_progress,
        status, created_game_day
      ) VALUES ($1, $2, $3, 'private', $4, $5, $6, $7, 100.0, $8, 'balanced', true, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, 0.0, 'under_construction', $21)`,
      [
        buildingId,
        citizenCityId,
        input.ownerId,
        catalogId,
        input.buildingType,
        input.name.trim() || spec.name,
        spec.tier,
        spec.slotFootprint,
        spec.dailyEnergyUpkeep,
        spec.dailyFoodUpkeep,
        spec.dailyMaterialsUpkeep,
        spec.dailyComponentsUpkeep,
        spec.dailyComputeUpkeep,
        spec.dailyStaffingCredits,
        spec.resourceOutputType,
        spec.resourceOutputAmount,
        day,
        completeDay,
        currentTotalMinute,
        completeMinute,
        day,
      ],
    );

    // Record timestamped rate change snapshot
    await tx.query('SELECT * FROM earth_record_rate_change($1, $2, $3, $4, $5)', [
      input.ownerId,
      'building_construction',
      buildingId,
      day,
      0,
    ]);

    const created = await tx.query('SELECT * FROM buildings WHERE id = $1', [buildingId]);
    return {
      ok: true,
      building: created.rows[0],
      correlationId: input.correlationId,
    };
  });
}

export async function upgradeBuilding(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'building_upgrade' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const existing = await tx.query('SELECT * FROM buildings WHERE id = $1', [input.buildingId]);
      return { ok: true, alreadyProcessed: true, building: existing.rows[0], correlationId: input.correlationId };
    }

    const bldRes = await tx.query<{
      id: string;
      owner_id: string;
      city_id: string | null;
      building_type: string;
      tier: number;
      resource_output_amount: string;
      daily_operating_credits: string;
      status: string;
    }>('SELECT * FROM buildings WHERE id = $1 FOR UPDATE', [input.buildingId]);
    const bld = bldRes.rows[0];
    if (!bld) throw new Error('Building not found');
    if (bld.owner_id !== input.humanId) throw new Error('Only the property owner can upgrade this facility');
    const nextTier = bld.tier + 1;
    const spec = BUILDING_CATALOG[bld.building_type];
    const tierSpec = spec?.tiers?.find((t) => t.tier === nextTier);
    const targetCatalog = await tx.query<{
      id: string;
      name: string;
      research_project_id: string | null;
      cost_credits: string;
      cost_materials: string;
      cost_components: string;
      cost_compute: string;
      output_credits: string;
      output_energy: string;
      output_food: string;
      output_materials: string;
      output_components: string;
      output_compute: string;
      operating_credits: string;
    }>('SELECT id, name, research_project_id, cost_credits, cost_materials, cost_components, cost_compute, output_credits, output_energy, output_food, output_materials, output_components, output_compute, operating_credits FROM building_catalog WHERE id = $1', [`${bld.building_type}-t${nextTier}`]);
    // Tier upgrades are catalog-driven.  The static catalog may still contain
    // legacy tier definitions, but a tier must not become usable until its
    // researched/seeded database blueprint exists (and the buildings.catalog_id
    // foreign key can resolve it).
    if (!targetCatalog.rows[0]) {
      throw new Error(`Tier ${nextTier} is not available yet. Research this building tier first.`);
    }
    if (targetCatalog.rows[0]?.research_project_id) {
      const membership = await tx.query<{ corporation_id: string | null }>(
        'SELECT corporation_id FROM memberships WHERE human_id = $1 AND corporation_id IS NOT NULL LIMIT 1',
        [input.humanId],
      );
      const corporationId = membership.rows[0]?.corporation_id;
      if (!corporationId) throw new Error('This researched tier is available only to corporation members');
      const unlock = await tx.query(
        "SELECT 1 FROM corporation_building_unlocks WHERE corporation_id = $1 AND catalog_id = $2 AND status = 'unlocked'",
        [corporationId, targetCatalog.rows[0].id],
      );
      if (!unlock.rows[0]) throw new Error('Your corporation must complete this building research before using the tier');
    }

    if (bld.building_type !== 'private-estate-plot' && tierSpec?.requiredCityPopulation) {
      const popRes = await tx.query<{ count: string }>(
        'SELECT COUNT(*)::text AS count FROM memberships WHERE city_id = $1',
        [bld.city_id],
      );
      const population = Number(popRes.rows[0]?.count ?? 0);
      if (population < tierSpec.requiredCityPopulation) {
        throw new Error(`Tier ${nextTier} requires City Population of at least ${tierSpec.requiredCityPopulation} (Current: ${population})`);
      }
    }

    const upgradeCreditCost = tierSpec?.upgradeCreditCost ?? Number(targetCatalog.rows[0]?.cost_credits ?? 4800 * nextTier);
    const upgradeMaterialCost = tierSpec?.upgradeMaterialCost ?? Number(targetCatalog.rows[0]?.cost_materials ?? 0);
    const upgradeCompCost = tierSpec?.upgradeComponentsCost ?? Number(targetCatalog.rows[0]?.cost_components ?? 0);
    const upgradeComputeCost = tierSpec?.upgradeComputeCost ?? Number(targetCatalog.rows[0]?.cost_compute ?? 0);
    const catalogOutput = targetCatalog.rows[0];
    const newOutputAmount = tierSpec?.resourceOutputAmount ??
      (tierSpec?.resourceOutputType === 'credits' || !tierSpec?.resourceOutputType
        ? tierSpec?.dailyCreditRevenue ?? Number(catalogOutput?.output_credits ?? bld.resource_output_amount ?? 0)
        : 0);
    const newOpCredits = tierSpec?.dailyOperatingCredits ??
      Number(catalogOutput?.operating_credits ?? bld.daily_operating_credits ?? 0);

    const creditCostCents = BigInt(upgradeCreditCost * 100);
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Upgrade requires ${upgradeCreditCost} Credits`);
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    if (upgradeMaterialCost > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.humanId,
        resource: 'material',
        delta: -upgradeMaterialCost,
        reasonType: 'building_upgrade',
        reasonId: input.buildingId,
        correlationId: `${input.correlationId}:material`,
        gameDay: day,
      });
    }

    if (upgradeCompCost > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.humanId,
        resource: 'components',
        delta: -upgradeCompCost,
        reasonType: 'building_upgrade',
        reasonId: input.buildingId,
        correlationId: `${input.correlationId}:components`,
        gameDay: day,
      });
    }

    if (upgradeComputeCost > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.humanId,
        resource: 'compute',
        delta: -upgradeComputeCost,
        reasonType: 'building_upgrade',
        reasonId: input.buildingId,
        correlationId: `${input.correlationId}:compute`,
        gameDay: day,
      });
    }

    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: bld.building_type === 'private-estate-plot'
        ? 'account-ouc-treasury'
        : `account-city-${bld.city_id}`,
      amount: centsToMoney(creditCostCents),
      reasonType: 'building_upgrade',
      reasonId: bld.id,
      ruleVersion: 'real-estate-v2',
      correlationId: input.correlationId,
    });

    const newCatalogId = `${bld.building_type}-t${nextTier}`;

    await tx.query(
      `UPDATE buildings SET
        catalog_id = $1,
        tier = $2,
        name = COALESCE($3, name),
        resource_output_amount = $4,
        daily_operating_credits = $5,
        condition = 100.0,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $6`,
      [newCatalogId, nextTier, tierSpec?.name ?? catalogOutput?.name ?? null, newOutputAmount, newOpCredits, bld.id],
    );

    // Record timestamped rate change snapshot
    await tx.query('SELECT * FROM earth_record_rate_change($1, $2, $3, $4, $5)', [
      input.humanId,
      'building_upgrade',
      bld.id,
      day,
      0,
    ]);

    const updated = await tx.query('SELECT * FROM buildings WHERE id = $1', [bld.id]);
    return { ok: true, building: updated.rows[0], correlationId: input.correlationId };
  });
}

export async function completeBuildingConstruction(
  repository: PostgresRepository,
  input: { humanId: string; buildingId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const building = await tx.query<{
      id: string;
      owner_id: string;
      status: string;
      construction_complete_game_day: number | null;
      construction_complete_minute: number | null;
    }>('SELECT id, owner_id, status, construction_complete_game_day, construction_complete_minute FROM buildings WHERE id = $1 FOR UPDATE', [input.buildingId]);
    const bld = building.rows[0];
    if (!bld) throw new Error('Building not found');
    if (bld.owner_id !== input.humanId) throw new Error('Only the property owner can complete this construction');
    if (bld.status === 'active') {
      return { ok: true, alreadyCompleted: true, building: (await tx.query('SELECT * FROM buildings WHERE id = $1', [bld.id])).rows[0] };
    }

    const world = await tx.query<{ genesis_at: string; simulated_day_offset: number }>(
      "SELECT genesis_at, simulated_day_offset FROM world_state WHERE id = 'WORLD'",
    );
    const current = getAuthoritativeGameTime({
      genesisAt: world.rows[0]?.genesis_at,
      simulatedDayOffset: world.rows[0]?.simulated_day_offset,
    });
    const completeMinute = bld.construction_complete_minute ??
      ((Number(bld.construction_complete_game_day ?? current.gameDay) - 1) * 1440);
    if (current.totalGameMinutes < completeMinute) {
      throw new Error('Building construction is not finished yet');
    }

    const updated = await tx.query(
      "UPDATE buildings SET status = 'active', construction_progress = 100.0, condition = 100.0, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *",
      [bld.id],
    );
    return { ok: true, building: updated.rows[0] };
  });
}

export async function setBuildingOperatingPolicy(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
    policy: OperatingPolicy;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const bld = await tx.query<{ id: string; owner_id: string }>(
      'SELECT id, owner_id FROM buildings WHERE id = $1',
      [input.buildingId],
    );
    if (!bld.rows[0]) throw new Error('Building not found');
    if (bld.rows[0].owner_id !== input.humanId) throw new Error('Unauthorized');

    await tx.query(
      'UPDATE buildings SET operating_policy = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [input.policy, input.buildingId],
    );

    // Record timestamped rate change snapshot
    await tx.query('SELECT * FROM earth_record_rate_change($1, $2, $3, $4, $5)', [
      input.humanId,
      'policy_change',
      input.buildingId,
      null,
      null,
    ]);

    return { ok: true, buildingId: input.buildingId, policy: input.policy };
  });
}

export async function setBuildingAutoRepair(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
    autoRepairEnabled: boolean;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const bld = await tx.query<{ id: string; owner_id: string }>(
      'SELECT id, owner_id FROM buildings WHERE id = $1',
      [input.buildingId],
    );
    if (!bld.rows[0]) throw new Error('Building not found');
    if (bld.rows[0].owner_id !== input.humanId) throw new Error('Unauthorized');

    await tx.query(
      'UPDATE buildings SET auto_repair_enabled = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [input.autoRepairEnabled, input.buildingId],
    );

    return { ok: true, buildingId: input.buildingId, autoRepairEnabled: input.autoRepairEnabled };
  });
}

export async function repairBuilding(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const bld = await tx.query<{ id: string; owner_id: string; condition: string; tier: number }>(
      'SELECT id, owner_id, condition, tier FROM buildings WHERE id = $1 FOR UPDATE',
      [input.buildingId],
    );
    if (!bld.rows[0]) throw new Error('Building not found');
    if (bld.rows[0].owner_id !== input.humanId) throw new Error('Unauthorized');

    const currentCondition = Number(bld.rows[0].condition);
    if (currentCondition >= 100) return { ok: true, condition: 100, message: 'Facility is already in pristine condition' };

    const missingCondition = 100 - currentCondition;
    const requiredComponents = Math.max(1, Math.ceil((missingCondition / 10) * bld.rows[0].tier));

    await mutateResourceBalance(tx, {
      ownerId: input.humanId,
      resource: 'components',
      delta: -requiredComponents,
      reasonType: 'building_maintenance',
      reasonId: input.buildingId,
      correlationId: `repair-${input.buildingId}-${Date.now()}`,
    });

    await tx.query(
      "UPDATE buildings SET condition = 100.0, status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
      [input.buildingId],
    );

    return { ok: true, buildingId: input.buildingId, condition: 100.0, componentsUsed: requiredComponents };
  });
}

export async function demolishBuilding(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const bld = await tx.query<{ id: string; owner_id: string; building_type: string; slot_footprint: number }>(
      'SELECT id, owner_id, building_type, slot_footprint FROM buildings WHERE id = $1 FOR UPDATE',
      [input.buildingId],
    );
    if (!bld.rows[0]) throw new Error('Building not found');
    if (bld.rows[0].owner_id !== input.humanId) throw new Error('Only the owner can demolish this facility');
    if (bld.rows[0].building_type === 'private-estate-plot' || bld.rows[0].building_type === 'urban-district-module') {
      throw new Error('Permanent estate foundations and district infrastructure cannot be demolished');
    }

    const catalog = await tx.query<{ cost_materials: string }>(
      'SELECT cost_materials FROM building_catalog WHERE id = $1',
      [`${bld.rows[0].building_type}-t1`],
    );
    const recycledMaterials = Math.floor(Number(catalog.rows[0]?.cost_materials ?? 100) * 0.30);

    // Recycle materials back to owner with guaranteed ledger audit
    if (recycledMaterials > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.humanId,
        resource: 'material',
        delta: recycledMaterials,
        reasonType: 'building_demolition_salvage',
        reasonId: input.buildingId,
        correlationId: `demolish-${input.buildingId}-${Date.now()}`,
      });
    }

    await tx.query("UPDATE buildings SET status = 'closed', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [
      input.buildingId,
    ]);

    // Record timestamped rate change snapshot
    await tx.query('SELECT * FROM earth_record_rate_change($1, $2, $3, $4, $5)', [
      input.humanId,
      'building_demolition',
      input.buildingId,
      null,
      null,
    ]);

    return { ok: true, buildingId: input.buildingId, recycledMaterials, freedSlots: bld.rows[0].slot_footprint };
  });
}

/*
export async function getCivicDividendHistory(
  repository: PostgresRepository,
  cityId: string,
  humanId: string,
): Promise<Record<string, unknown>> {
  const payouts = await repository.query(
    'SELECT * FROM civic_dividend_payouts WHERE city_id = $1 ORDER BY day DESC LIMIT 10',
    [cityId],
  );

  const myShares = await repository.query(
    `SELECT s.*, b.name AS building_name, b.building_type, b.condition
     FROM building_investment_shares s
     JOIN buildings b ON s.building_id = b.id
     WHERE s.investor_id = $1 AND b.city_id = $2`,
    [humanId, cityId],
  );

  return {
    cityId,
    recentPayouts: payouts.rows,
    myShares: myShares.rows,
  };
}

*/
export async function contributeCorporateResearch(
  repository: PostgresRepository,
  input: {
    humanId: string;
    poolId: string;
    credits: number;
    compute: number;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'corp_research_contribution' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const pool = await tx.query('SELECT * FROM corporate_research_pools WHERE id = $1', [input.poolId]);
      return { ok: true, alreadyProcessed: true, pool: pool.rows[0], correlationId: input.correlationId };
    }

    const poolRes = await tx.query<{
      id: string;
      corporation_id: string;
      name: string;
      target_compute: string;
      target_credits: string;
      contributed_compute: string;
      contributed_credits: string;
      status: string;
    }>('SELECT * FROM corporate_research_pools WHERE id = $1 FOR UPDATE', [input.poolId]);
    const pool = poolRes.rows[0];
    if (!pool || pool.status !== 'active') throw new Error('Active corporate research pool not found');

    const membership = await tx.query<{ corporation_id: string | null }>(
      'SELECT corporation_id FROM memberships WHERE human_id = $1',
      [input.humanId],
    );
    if (membership.rows[0]?.corporation_id !== pool.corporation_id) {
      throw new Error('You are not a member of this corporation');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    if (input.credits > 0) {
      const creditCents = BigInt(Math.round(input.credits * 100));
      const account = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [input.humanId],
      );
      if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCents) {
        throw new Error('Insufficient Credits for R&D contribution');
      }
      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: account.rows[0].account_id,
        creditAccount: `account-corporation-${pool.corporation_id}`,
        amount: centsToMoney(creditCents),
        reasonType: 'corp_research_contribution',
        reasonId: pool.id,
        ruleVersion: 'corp-rd-v1',
        correlationId: input.correlationId,
      });
    }

    if (input.compute > 0) {
      await mutateResourceBalance(tx, {
        ownerId: input.humanId,
        resource: 'compute',
        delta: -input.compute,
        reasonType: 'corporate_research_funding',
        reasonId: pool.id,
        correlationId: `rd-compute-${pool.id}-${input.humanId}-${Date.now()}`,
      });
    }

    const newCredits = Number(pool.contributed_credits) + Math.max(0, input.credits);
    const newCompute = Number(pool.contributed_compute) + Math.max(0, input.compute);
    const completed = newCredits >= Number(pool.target_credits) && newCompute >= Number(pool.target_compute);

    await tx.query(
      `UPDATE corporate_research_pools SET
        contributed_credits = $1,
        contributed_compute = $2,
        status = CASE WHEN $3 THEN 'completed' ELSE 'active' END,
        completed_game_day = CASE WHEN $3 THEN $4 ELSE NULL END,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $5`,
      [newCredits, newCompute, completed, day, pool.id],
    );

    const updated = await tx.query('SELECT * FROM corporate_research_pools WHERE id = $1', [pool.id]);
    return { ok: true, pool: updated.rows[0], completed, correlationId: input.correlationId };
  });
}
