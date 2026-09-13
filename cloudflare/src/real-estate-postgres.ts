import type { PostgresRepository } from './repository.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';
import { postEconomicCreditTransfer } from './financial-postgres.ts';
import { postEconomicResourceMutation } from './resource-ledger-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import type { OperatingPolicy } from './real-estate-catalog.ts';
import { createGameEvent } from './game-events-postgres.ts';

type ConstructionTechnologySnapshot = {
  rulesVersion: string | null;
  modifiers: Record<string, number>;
};

function constructionModifier(
  modifiers: Record<string, number>,
  effectType: string,
  targetKey: string,
): number {
  return Number(
    modifiers[`${effectType}:ASSET:${targetKey}`]
      ?? modifiers[`${effectType}:ASSET:ALL`]
      ?? modifiers[`${effectType}:ALL_BUILDINGS:ALL`]
      ?? modifiers[`${effectType}:ALL:ALL`]
      ?? 0,
  );
}
async function resolveConstructionTechnology(
  tx: PostgresRepository,
  ownerId: string,
  gameDay: number,
): Promise<ConstructionTechnologySnapshot> {
  const result = await tx.query<{
    rules_version: string | null;
    modifiers: Record<string, number> | null;
  }>(
    `SELECT NULL::TEXT AS rules_version, '{}'::JSONB AS modifiers
       FROM house_affiliations
      WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)
        AND corporation_id IS NOT NULL
        AND status = 'ACTIVE'
      LIMIT 1`,
    [ownerId, gameDay],
  );
  const row = result.rows[0];
  return { rulesVersion: row?.rules_version ?? null, modifiers: row?.modifiers ?? {} };
}
export interface DistrictZoningSummary {
  cityId: string;
  cityName: string | null;
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
    `SELECT c.id, i.name
       FROM cities c JOIN institutions i ON i.id = c.id
      WHERE c.id = $1`,
    [cityId],
  );
  const city = cityRes.rows[0];
  const cityName = city?.name ?? null;

  const popRes = await repository.query<{ count: string }>(
    "SELECT COUNT(*)::integer AS count FROM house_affiliations WHERE city_id = $1 AND status = 'ACTIVE'",
    [cityId],
  );
  const population = Number(popRes.rows[0]?.count ?? 0);

  const districtEffects = await repository.query<{ district_count: string; citizen_capacity: string; total_slots: string; civic_reserved_slots: string }>(
    `SELECT COUNT(*)::text FILTER (WHERE b.catalog_id LIKE 'URBAN-DISTRICT%') AS district_count,
            COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CITY_CITIZEN_CAPACITY'), 0)::text AS citizen_capacity,
            COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CITY_TOTAL_SLOTS'), 0)::text AS total_slots,
            COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CITY_CIVIC_RESERVED_SLOTS'), 0)::text AS civic_reserved_slots
       FROM buildings b LEFT JOIN building_catalog_effects e ON e.catalog_id = b.catalog_id
      WHERE b.city_id = $1 AND b.status = 'ACTIVE'`,
    [cityId],
  );
  const districtModulesCount = Number(districtEffects.rows[0]?.district_count ?? 0);
  const maxCitizens = Number(districtEffects.rows[0]?.citizen_capacity ?? 0);
  const totalSlots = Number(districtEffects.rows[0]?.total_slots ?? 0);
  const civicReservedSlots = Number(districtEffects.rows[0]?.civic_reserved_slots ?? 0);

  const bldRes = await repository.query<{
    id: string;
    owner_economic_id: string;
    catalog_id: string;
    slot_footprint: number;
  }>(
    "SELECT b.id, b.owner_economic_id, b.catalog_id, c.slot_footprint FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id WHERE b.city_id = $1 AND b.status = 'ACTIVE'",
    [cityId],
  );
  const personalEstateRes = viewerId
    ? await repository.query<{ slots: string }>(
        `SELECT COALESCE(SUM(e.effect_value), 0)::text AS slots
           FROM buildings b JOIN building_catalog_effects e ON e.catalog_id = b.catalog_id
          WHERE b.owner_economic_id = (SELECT h.house_id FROM humans h WHERE h.id = $1)
            AND b.status = 'ACTIVE' AND e.effect_code = 'PRIVATE_OWNER_SLOTS'`,
        [viewerId],
      )
    : { rows: [] as Array<{ slots: string }> };

  let usedPrivateSlots = 0;
  let usedCivicSlots = 0;
  const personalOwnerSlots = Number(personalEstateRes.rows[0]?.slots ?? 0);
  const personalEstateTier = personalOwnerSlots > 0 ? Math.ceil(personalOwnerSlots / 10) : undefined;
  let personalUsedSlots = 0;

  for (const row of bldRes.rows) {
    const footprint = Math.max(0, Number(row.slot_footprint || 0));
    usedPrivateSlots += footprint;
    if (viewerId && row.owner_economic_id === `HOUSE-${viewerId.replace(/^H-/, '')}`) personalUsedSlots += footprint;
  }

  const maxPrivatePermitted = Math.max(0, totalSlots - civicReservedSlots);
  const availablePrivateSlots = Math.max(0, maxPrivatePermitted - usedPrivateSlots);
  const availableCivicSlots = Math.max(0, totalSlots - usedCivicSlots - usedPrivateSlots);

  const personalMaxSlots = personalOwnerSlots;
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
  return purchaseBaselineBuilding(repository, input);
}

async function purchaseBaselineBuilding(
  repository: PostgresRepository,
  input: { ownerId: string; cityId: string; buildingType: string; name: string; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ source_id: string }>(
      'SELECT source_id FROM economic_transactions WHERE correlation_id = $1', [input.correlationId],
    );
    if (prior.rows[0]?.source_id) {
      const existing = await tx.query('SELECT * FROM buildings WHERE id = $1', [prior.rows[0].source_id]);
      return { ok: true, alreadyProcessed: true, building: existing.rows[0], correlationId: input.correlationId };
    }
    const catalog = (await tx.query<{
      id: string; code: string; construction_credit_units: string; construction_minutes: number;
      resource_input_units: Record<string, number>;
    }>(
      `SELECT id, code, construction_credit_units, construction_minutes, resource_input_units
         FROM building_catalog
        WHERE id = $1 OR code = $1 OR lower(code) = lower($1)
        LIMIT 1`, [input.buildingType],
    )).rows[0];
    if (!catalog) throw new Error('Unknown or inactive building blueprint');
    const owner = (await tx.query<{ economic_id: string }>(
      `SELECT o.economic_id FROM humans h JOIN owner_registry o ON o.id = h.house_id
        WHERE h.id = $1 AND h.status = 'ACTIVE'`, [input.ownerId],
    )).rows[0];
    if (!owner) throw new Error('House economic owner not found');
    const city = (await tx.query('SELECT 1 FROM cities WHERE id = $1 AND status = \'ACTIVE\'', [input.cityId])).rows[0];
    if (!city) throw new Error('City not found or inactive');
    const wallet = (await tx.query<{ id: string; balance_units: string }>(
      `SELECT id::TEXT, balance_units::TEXT FROM economic_accounts
        WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE`,
      [owner.economic_id],
    )).rows[0];
    const cost = BigInt(catalog.construction_credit_units);
    if (!wallet || BigInt(wallet.balance_units) < cost) throw new Error(`Insufficient Credits for construction (Requires ${catalog.construction_credit_units} units)`);
    const treasury = (await tx.query<{ id: string }>(
      `SELECT a.id::TEXT AS id FROM economic_accounts a
         JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.id = 'OUC' AND a.asset_id = 1 AND a.account_type = 'TREASURY' AND a.status = 'ACTIVE' LIMIT 1`,
    )).rows[0];
    if (!treasury) throw new Error('OUC treasury account is not configured');
    const world = (await tx.query<{ game_day: string; game_minute: number }>("SELECT game_day::TEXT, game_minute FROM world_state WHERE id = 'WORLD'")).rows[0];
    const day = Number(world?.game_day ?? 1);
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const post = async (correlationId: string, sourceId: string, entries: Array<{ account_id: string; asset_id: number; delta_units: string }>) => {
      await tx.query(
        `SELECT earth_post_transaction($1,$2,$3,'BUILDING_CONSTRUCTION','HOUSE',$4,'building-v2',$5::JSONB)`,
        [correlationId, day, Number(world?.game_minute ?? 0), sourceId, JSON.stringify(entries)],
      );
    };
    await post(input.correlationId, buildingId, [
      { account_id: wallet.id, asset_id: 1, delta_units: (-cost).toString() },
      { account_id: treasury.id, asset_id: 1, delta_units: cost.toString() },
    ]);
    const inputs = catalog.resource_input_units ?? {};
    for (const [code, rawAmount] of Object.entries(inputs)) {
      const amount = BigInt(Math.max(0, Math.round(Number(rawAmount))));
      if (amount === 0n) continue;
      const asset = (await tx.query<{ id: number }>('SELECT id FROM economic_assets WHERE code = $1', [code.toUpperCase()])).rows[0];
      if (!asset) throw new Error(`Unknown construction resource ${code}`);
      const inventory = (await tx.query<{ id: string; balance_units: string }>(
        `SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = $2 AND account_type = 'INVENTORY' AND status = 'ACTIVE' FOR UPDATE`,
        [owner.economic_id, asset.id],
      )).rows[0];
      if (!inventory || BigInt(inventory.balance_units) < amount) throw new Error(`Insufficient ${code} for construction`);
      const sink = (await tx.query<{ id: string }>(
        `SELECT a.id::TEXT AS id FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
          WHERE o.owner_type = 'SYSTEM' AND a.asset_id = $1 AND a.account_type = 'INVENTORY' AND a.status = 'ACTIVE' LIMIT 1`, [asset.id],
      )).rows[0];
      if (!sink) throw new Error(`Resource sink is not configured for ${code}`);
      await post(`${input.correlationId}:resource:${code}`, buildingId, [
        { account_id: inventory.id, asset_id: asset.id, delta_units: (-amount).toString() },
        { account_id: sink.id, asset_id: asset.id, delta_units: amount.toString() },
      ]);
    }
    await tx.query(
      `INSERT INTO buildings (id, owner_economic_id, catalog_id, city_id, status, started_game_day)
       VALUES ($1,$2,$3,$4,'ACTIVE',$5)`,
      [buildingId, owner.economic_id, catalog.id, input.cityId, day],
    );
    await createGameEvent(tx, {
      id: `BUILDING-ACQUIRED-${input.correlationId}`,
      category: 'BUILDING',
      eventType: 'BUILDING_ACQUIRED',
      gameDay: day,
      actorHumanId: input.ownerId,
      subjectType: 'BUILDING',
      subjectId: buildingId,
      title: `${catalog.code} acquired`,
      details: { buildingId, catalogId: catalog.id, cityId: input.cityId, ownerEconomicId: owner.economic_id },
      correlationId: input.correlationId,
    });
    const created = await tx.query('SELECT * FROM buildings WHERE id = $1', [buildingId]);
    return { ok: true, building: created.rows[0], correlationId: input.correlationId };
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
      "SELECT source_id AS reason_id FROM economic_transactions WHERE transaction_kind = 'building_upgrade' AND correlation_id = $1",
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
    const targetCatalog = await tx.query<{
      id: string;
      building_type: string;
      name: string;
      tier: number;
      ownership_class: string;
      slot_footprint: number;
      research_project_id: string | null;
      cost_credits: string;
      cost_materials: string;
      cost_components: string;
      cost_compute: string;
      output_energy: string;
      output_food: string;
      output_materials: string;
      output_components: string;
      output_compute: string;
      upkeep_energy: string;
      upkeep_food: string;
      upkeep_materials: string;
      upkeep_components: string;
      upkeep_compute: string;
      operating_credits: string;
    }>('SELECT id, building_type, name, tier, ownership_class, slot_footprint, research_project_id, cost_credits, cost_materials, cost_components, cost_compute, output_energy, output_food, output_materials, output_components, output_compute, upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute, operating_credits FROM building_catalog WHERE id = $1 AND tier = $2 AND is_active = true', [`${bld.building_type}-t${nextTier}`, nextTier]);
    // Tier upgrades are catalog-driven. The catalog may contain future tier
    // definitions, but a tier must not become usable until its
    // researched/seeded database blueprint exists (and the buildings.catalog_id
    // foreign key can resolve it).
    if (!targetCatalog.rows[0]) {
      throw new Error(`Tier ${nextTier} is not available yet. Research this building tier first.`);
    }
    if (targetCatalog.rows[0]?.research_project_id) {
      const membership = await tx.query<{ corporation_id: string | null }>(
      'SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = \'ACTIVE\' AND ha.corporation_id IS NOT NULL LIMIT 1',
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

    const upgradeCreditCost = Number(targetCatalog.rows[0].cost_credits ?? 0);
    const upgradeMaterialCost = Number(targetCatalog.rows[0].cost_materials ?? 0);
    const upgradeCompCost = Number(targetCatalog.rows[0].cost_components ?? 0);
    const upgradeComputeCost = Number(targetCatalog.rows[0].cost_compute ?? 0);
    const catalogOutput = targetCatalog.rows[0];
    const outputCandidates = [
      ['energy', catalogOutput.output_energy], ['food', catalogOutput.output_food],
      ['material', catalogOutput.output_materials], ['components', catalogOutput.output_components],
      ['compute', catalogOutput.output_compute],
    ] as const;
    const newOutput = outputCandidates.find(([, amount]) => Number(amount ?? 0) > 0);
    const newOutputType = newOutput?.[0] ?? null;
    const newOutputAmount = Number(newOutput?.[1] ?? 0);
    const newOpCredits = Number(catalogOutput.operating_credits ?? 0);

    const creditCostCents = BigInt(upgradeCreditCost * 100);
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT a.id::TEXT AS account_id, a.balance_units::TEXT AS balance FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' FOR UPDATE",
      [input.humanId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Upgrade requires ${upgradeCreditCost} Credits`);
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    if (upgradeMaterialCost > 0) {
      await postEconomicResourceMutation(tx, {
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
      await postEconomicResourceMutation(tx, {
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
      await postEconomicResourceMutation(tx, {
        ownerId: input.humanId,
        resource: 'compute',
        delta: -upgradeComputeCost,
        reasonType: 'building_upgrade',
        reasonId: input.buildingId,
        correlationId: `${input.correlationId}:compute`,
        gameDay: day,
      });
    }

    await postEconomicCreditTransfer(tx, {
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
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $6`,
      [newCatalogId, nextTier, tierSpec?.name ?? catalogOutput?.name ?? null, newOutputAmount, newOpCredits, bld.id],
    );

    // Invalidate the profile and record the V2 rate change atomically.
    await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [
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
      "UPDATE buildings SET status = 'active', construction_progress = 100.0, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *",
      [bld.id],
    );
    await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [
      bld.owner_id,
      bld.id,
      'construction_completed',
      current.gameDay,
      current.gameMinute,
    ]);
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

    // Invalidate the profile and record the V2 rate change atomically.
    await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [
      input.humanId,
      'policy_change',
      input.buildingId,
      null,
      null,
    ]);

    return { ok: true, buildingId: input.buildingId, policy: input.policy };
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
      await postEconomicResourceMutation(tx, {
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

    // Invalidate the profile and record the V2 rate change atomically.
    await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [
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
    `SELECT s.*, b.name AS building_name, b.building_type
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
      "SELECT source_id AS reason_id FROM economic_transactions WHERE transaction_kind = 'corp_research_contribution' AND correlation_id = $1",
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
      'SELECT ha.corporation_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id WHERE h.id = $1 AND ha.status = \'ACTIVE\' LIMIT 1',
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
        "SELECT a.id::TEXT AS account_id, a.balance_units::TEXT AS balance FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' FOR UPDATE",
        [input.humanId],
      );
      if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCents) {
        throw new Error('Insufficient Credits for R&D contribution');
      }
      await postEconomicCreditTransfer(tx, {
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
      await postEconomicResourceMutation(tx, {
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
        status = CASE WHEN $3::boolean THEN 'completed' ELSE 'active' END,
        completed_game_day = CASE WHEN $3::boolean THEN $4 ELSE NULL END,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $5`,
      [newCredits, newCompute, completed, day, pool.id],
    );

    const updated = await tx.query('SELECT * FROM corporate_research_pools WHERE id = $1', [pool.id]);
    return { ok: true, pool: updated.rows[0], completed, correlationId: input.correlationId };
  });
}
