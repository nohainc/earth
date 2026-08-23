import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import {
  BUILDING_CATALOG,
  type OperatingPolicy,
  type OwnershipClass,
  type RequiredPatentSpec,
} from './real-estate-catalog.ts';

export function findPatentSpecInCatalog(patentId: string): RequiredPatentSpec | null {
  for (const item of Object.values(BUILDING_CATALOG)) {
    if (item.requiredPatent && item.requiredPatent.patentId === patentId) {
      return item.requiredPatent;
    }
    for (const tier of item.tiers || []) {
      if (tier.requiredPatent && tier.requiredPatent.patentId === patentId) {
        return tier.requiredPatent;
      }
    }
  }
  return null;
}

export async function checkBuildingPatentAccess(
  tx: any,
  input: {
    humanId: string;
    cityId: string;
    requiredPatent?: RequiredPatentSpec | null;
  },
): Promise<{
  hasAccess: boolean;
  accessType: 'foundational' | 'corporate_member' | 'private_building' | 'city_civic' | 'none';
  patent?: RequiredPatentSpec;
}> {
  if (!input.requiredPatent) {
    return { hasAccess: true, accessType: 'foundational' };
  }

  const req = input.requiredPatent;

  // 1. Check corporate membership
  const memberRes = await tx.query(
    "SELECT corporation_id FROM memberships WHERE human_id = $1 AND corporation_id = $2 AND status = 'active'",
    [input.humanId, req.owningCorporationId],
  );
  if (memberRes.rows && memberRes.rows.length > 0) {
    return { hasAccess: true, accessType: 'corporate_member', patent: req };
  }

  // 2. Check private building license
  const privRes = await tx.query(
    "SELECT * FROM building_patent_licenses WHERE licensee_id = $1 AND patent_id = $2 AND status IN ('active', 'renewal_window')",
    [input.humanId, req.patentId],
  );
  if (privRes.rows && privRes.rows.length > 0) {
    return { hasAccess: true, accessType: 'private_building', patent: req };
  }

  // 3. Check city-wide civic license
  const cityRes = await tx.query(
    "SELECT * FROM building_patent_licenses WHERE city_id = $1 AND patent_id = $2 AND status IN ('active', 'renewal_window')",
    [input.cityId, req.patentId],
  );
  if (cityRes.rows && cityRes.rows.length > 0) {
    return { hasAccess: true, accessType: 'city_civic', patent: req };
  }

  return { hasAccess: false, accessType: 'none', patent: req };
}

export interface DistrictZoningSummary {
  cityId: string;
  cityName: string;
  population: number;
  totalSlots: number;
  civicReservedSlots: number;
  usedPrivateSlots: number;
  usedCivicSlots: number;
  availablePrivateSlots: number;
  availableCivicSlots: number;
  buildingsCount: number;
}

/**
 * Calculates authoritative dynamic city zoning slots and anti-monopoly quotas.
 * Total Slots = 8 + floor(activePopulation / 5) + infrastructureBonuses.
 * Minimum 30% of total slots are reserved exclusively for Civic & Public Megaprojects.
 */
export async function getCityDistrictZoning(
  repository: PostgresRepository,
  cityId: string,
): Promise<DistrictZoningSummary> {
  const cityRes = await repository.query<{ id: string; name: string }>(
    'SELECT id, name FROM cities WHERE id = $1',
    [cityId],
  );
  const city = cityRes.rows[0];
  const cityName = city?.name ?? 'Metropolitan District';

  const popRes = await repository.query<{ count: string }>(
    "SELECT COUNT(*)::integer AS count FROM memberships WHERE city_id = $1 AND status = 'active'",
    [cityId],
  );
  const population = Number(popRes.rows[0]?.count ?? 1);

  // Dynamic capacity formula: 8 + floor(pop / 5)
  const totalSlots = 8 + Math.floor(population / 5);
  const civicReservedSlots = Math.max(2, Math.ceil(totalSlots * 0.30));

  const bldRes = await repository.query<{
    slot_footprint: number;
    ownership_class: string;
  }>(
    "SELECT slot_footprint, ownership_class FROM buildings WHERE city_id = $1 AND status NOT IN ('closed', 'foreclosed')",
    [cityId],
  );

  let usedPrivateSlots = 0;
  let usedCivicSlots = 0;

  for (const row of bldRes.rows) {
    const footprint = Math.max(1, Number(row.slot_footprint || 1));
    const oClass = (row.ownership_class || 'private').toLowerCase();
    if (oClass === 'private') {
      usedPrivateSlots += footprint;
    } else {
      usedCivicSlots += footprint;
    }
  }

  const maxPrivatePermitted = Math.max(0, totalSlots - civicReservedSlots);
  const availablePrivateSlots = Math.max(0, maxPrivatePermitted - usedPrivateSlots);
  const availableCivicSlots = Math.max(0, totalSlots - usedCivicSlots - usedPrivateSlots);

  return {
    cityId,
    cityName,
    population,
    totalSlots,
    civicReservedSlots,
    usedPrivateSlots,
    usedCivicSlots,
    availablePrivateSlots,
    availableCivicSlots,
    buildingsCount: bldRes.rows.length,
  };
}

export async function purchasePrivatePlotAndConstruct(
  repository: PostgresRepository,
  input: {
    ownerId: string;
    cityId: string;
    buildingType: string;
    name: string;
    businessId?: string | null;
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

    const spec = BUILDING_CATALOG[input.buildingType];
    if (!spec) throw new Error('Unknown building archetype');
    if (spec.defaultOwnershipClass === 'civic') {
      throw new Error('Civic utility buildings must be procured via Democratic City Referendum');
    }

    const membership = await tx.query<{ city_id: string | null; corporation_id: string | null }>(
      'SELECT city_id, corporation_id FROM memberships WHERE human_id = $1',
      [input.ownerId],
    );
    const citizenCityId = membership.rows[0]?.city_id ?? input.cityId;

    // Check Corporate Patent Access (if required)
    if (spec.requiredPatent) {
      const patentAccess = await checkBuildingPatentAccess(tx, {
        humanId: input.ownerId,
        cityId: citizenCityId,
        requiredPatent: spec.requiredPatent,
      });
      if (!patentAccess.hasAccess) {
        throw new Error(
          `Construction locked: Requires Patent "${spec.requiredPatent.patentName}". Join ${spec.requiredPatent.owningCorporationName}, acquire a private license (${spec.requiredPatent.privateLicenseCostCrd} CRD), or request city civic procurement.`,
        );
      }
    }

    // Check District Zoning Capacity
    const zoning = await getCityDistrictZoning(repository, citizenCityId);
    if (zoning.availablePrivateSlots < spec.slotFootprint) {
      throw new Error(
        `City district capacity exceeded. This building requires ${spec.slotFootprint} slots, but only ${zoning.availablePrivateSlots} private slots are available in ${zoning.cityName}.`,
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
    const materialBal = await tx.query<{ amount: string }>(
      "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'material' FOR UPDATE",
      [input.ownerId],
    );
    const currentMaterials = Number(materialBal.rows[0]?.amount ?? 0);
    if (currentMaterials < materialCost) {
      throw new Error(`Insufficient Materials for construction (Requires ${materialCost} Materials)`);
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);
    const buildingId = `BLD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    // Transfer Credits (60% to City Treasury, 25% to Corp Treasury if affiliated, 15% to OUC)
    const costMoney = centsToMoney(creditCostCents);
    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: `account-city-${citizenCityId}`,
      amount: costMoney,
      reasonType: 'building_purchase',
      reasonId: buildingId,
      ruleVersion: 'real-estate-v2',
      correlationId: input.correlationId,
    });

    // Deduct Materials
    await tx.query(
      "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'",
      [materialCost, input.ownerId],
    );

    // Calculate construction timeline
    const constructionDays = Math.max(1, spec.slotFootprint);
    const completeDay = day + constructionDays;

    // Insert Self-Contained Building
    await tx.query(
      `INSERT INTO buildings (
        id, city_id, owner_id, ownership_class, business_id,
        building_type, name, tier, condition, slot_footprint,
        operating_policy, auto_repair_enabled,
        upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
        daily_operating_credits,
        resource_output_type, resource_output_amount,
        construction_started_game_day, construction_complete_game_day, construction_progress,
        status, created_game_day
      ) VALUES ($1, $2, $3, 'private', $4, $5, $6, $7, 100.0, $8, 'balanced', true, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, 0.0, 'under_construction', $19)`,
      [
        buildingId,
        citizenCityId,
        input.ownerId,
        input.businessId ?? null,
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
        day,
      ],
    );

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
      city_id: string;
      building_type: string;
      tier: number;
      resource_output_amount: string;
      daily_operating_credits: string;
      status: string;
    }>('SELECT * FROM buildings WHERE id = $1 FOR UPDATE', [input.buildingId]);
    const bld = bldRes.rows[0];
    if (!bld) throw new Error('Building not found');
    if (bld.owner_id !== input.humanId) throw new Error('Only the property owner can upgrade this facility');
    if (bld.tier >= 4) throw new Error('Building is already at maximum engineering tier (Tier 4)');

    const nextTier = bld.tier + 1;
    const spec = BUILDING_CATALOG[bld.building_type];
    const tierSpec = spec?.tiers?.find((t) => t.tier === nextTier);

    if (tierSpec?.requiredPatent) {
      const patentAccess = await checkBuildingPatentAccess(tx, {
        humanId: input.humanId,
        cityId: bld.city_id,
        requiredPatent: tierSpec.requiredPatent,
      });
      if (!patentAccess.hasAccess) {
        throw new Error(
          `Tier ${nextTier} upgrade locked: Requires Patent "${tierSpec.requiredPatent.patentName}". Join ${tierSpec.requiredPatent.owningCorporationName} or acquire a private building license (${tierSpec.requiredPatent.privateLicenseCostCrd} CRD).`,
        );
      }
    }

    if (tierSpec?.requiredCityPopulation) {
      const popRes = await tx.query<{ count: string }>(
        'SELECT COUNT(*)::text AS count FROM memberships WHERE city_id = $1',
        [bld.city_id],
      );
      const population = Number(popRes.rows[0]?.count ?? 0);
      if (population < tierSpec.requiredCityPopulation) {
        throw new Error(`Tier ${nextTier} requires City Population of at least ${tierSpec.requiredCityPopulation} (Current: ${population})`);
      }
    }

    const upgradeCreditCost = tierSpec?.upgradeCreditCost || 4800 * nextTier;
    const upgradeCompCost = tierSpec?.upgradeComponentsCost || 20 * nextTier;

    const creditCostCents = BigInt(upgradeCreditCost * 100);
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Upgrade requires ${upgradeCreditCost} Credits`);
    }

    if (upgradeCompCost > 0) {
      const compBal = await tx.query<{ amount: string }>(
        "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE",
        [input.humanId],
      );
      if (Number(compBal.rows[0]?.amount ?? 0) < upgradeCompCost) {
        throw new Error(`Upgrade requires ${upgradeCompCost} Components`);
      }

      await tx.query(
        "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components'",
        [upgradeCompCost, input.humanId],
      );
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: `account-city-${bld.city_id}`,
      amount: centsToMoney(creditCostCents),
      reasonType: 'building_upgrade',
      reasonId: bld.id,
      ruleVersion: 'real-estate-v2',
      correlationId: input.correlationId,
    });

    const newOutputAmount = tierSpec?.resourceOutputAmount ?? (Number(bld.resource_output_amount || 0) * 1.30);
    const newOpCredits = tierSpec?.dailyOperatingCredits ?? Number(bld.daily_operating_credits || 0);

    await tx.query(
      `UPDATE buildings SET
        tier = $1,
        resource_output_amount = $2,
        daily_operating_credits = $3,
        condition = 100.0,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $4`,
      [nextTier, newOutputAmount, newOpCredits, bld.id],
    );

    const updated = await tx.query('SELECT * FROM buildings WHERE id = $1', [bld.id]);
    return { ok: true, building: updated.rows[0], correlationId: input.correlationId };
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

    return { ok: true, buildingId: input.buildingId, policy: input.policy };
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

    const compBal = await tx.query<{ amount: string }>(
      "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE",
      [input.humanId],
    );
    if (Number(compBal.rows[0]?.amount ?? 0) < requiredComponents) {
      throw new Error(`Repair requires ${requiredComponents} Components to restore to 100%`);
    }

    await tx.query(
      "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components'",
      [requiredComponents, input.humanId],
    );

    await tx.query(
      "UPDATE buildings SET condition = 100.0, status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
      [input.buildingId],
    );

    return { ok: true, buildingId: input.buildingId, condition: 100.0, componentsUsed: requiredComponents };
  });
}

export async function investInPublicBuilding(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
    sharesCount: number;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'public_building_investment' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const shareRecord = await tx.query(
        'SELECT * FROM building_investment_shares WHERE building_id = $1 AND investor_id = $2',
        [input.buildingId, input.humanId],
      );
      return { ok: true, alreadyProcessed: true, shares: shareRecord.rows[0], correlationId: input.correlationId };
    }

    const bldRes = await tx.query<{
      id: string;
      city_id: string;
      ownership_class: string;
      name: string;
      resource_output_amount: string;
    }>('SELECT * FROM buildings WHERE id = $1', [input.buildingId]);
    const bld = bldRes.rows[0];
    if (!bld) throw new Error('Public investment facility not found');
    if (bld.ownership_class !== 'public_investment') {
      throw new Error('This facility is not an open public investment project');
    }

    const sharePrice = 500; // 500 Credits per share
    const totalCredits = input.sharesCount * sharePrice;
    const creditCostCents = BigInt(totalCredits * 100);

    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Insufficient Credits for share investment (Requires ${totalCredits} CRD)`);
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: `account-city-${bld.city_id}`,
      amount: centsToMoney(creditCostCents),
      reasonType: 'public_building_investment',
      reasonId: bld.id,
      ruleVersion: 'real-estate-v2',
      correlationId: input.correlationId,
    });

    const shareId = `SHR-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query(
      `INSERT INTO building_investment_shares (
        id, building_id, investor_id, shares_owned, total_shares_issued, invested_credits, created_game_day
      ) VALUES ($1, $2, $3, $4, 1000, $5, $6)
      ON CONFLICT (building_id, investor_id) DO UPDATE SET
        shares_owned = building_investment_shares.shares_owned + EXCLUDED.shares_owned,
        invested_credits = building_investment_shares.invested_credits + EXCLUDED.invested_credits,
        updated_at = CURRENT_TIMESTAMP`,
      [shareId, bld.id, input.humanId, input.sharesCount, totalCredits, day],
    );

    const updated = await tx.query(
      'SELECT * FROM building_investment_shares WHERE building_id = $1 AND investor_id = $2',
      [bld.id, input.humanId],
    );

    return { ok: true, shares: updated.rows[0], correlationId: input.correlationId };
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

    const spec = BUILDING_CATALOG[bld.rows[0].building_type];
    const recycledMaterials = Math.floor((spec?.baseMaterialCost ?? 100) * 0.30);

    // Recycle materials back to owner
    await tx.query(
      "UPDATE resource_balances SET amount = amount + $1 WHERE owner_id = $2 AND resource = 'material'",
      [recycledMaterials, input.humanId],
    );

    await tx.query("UPDATE buildings SET status = 'closed', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [
      input.buildingId,
    ]);

    return { ok: true, buildingId: input.buildingId, recycledMaterials, freedSlots: bld.rows[0].slot_footprint };
  });
}

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
      const compBal = await tx.query<{ amount: string }>(
        "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'compute' FOR UPDATE",
        [input.humanId],
      );
      if (Number(compBal.rows[0]?.amount ?? 0) < input.compute) {
        throw new Error('Insufficient Compute for R&D contribution');
      }
      await tx.query(
        "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'compute'",
        [input.compute, input.humanId],
      );
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

export async function acquireBuildingPatentLicense(
  repository: PostgresRepository,
  input: {
    humanId: string;
    patentId: string;
    licenseType: 'private_building' | 'city_civic';
    buildingId?: string | null;
    cityId?: string | null;
    isPermanent?: boolean;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'patent_license_purchase' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const existing = await tx.query('SELECT * FROM building_patent_licenses WHERE id = $1', [prior.rows[0].reason_id]);
      return { ok: true, alreadyProcessed: true, license: existing.rows[0], correlationId: input.correlationId };
    }

    const patentSpec = findPatentSpecInCatalog(input.patentId);
    if (!patentSpec) throw new Error(`Patent "${input.patentId}" not found in catalog`);

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    const isCivic = input.licenseType === 'city_civic';
    let licenseeId = input.humanId;

    if (isCivic) {
      const targetCityId = input.cityId;
      if (!targetCityId) throw new Error('City ID is required for civic patent licensing');

      // Check civic governance authorization or membership
      const authRes = await tx.query(
        `SELECT 1 FROM authority_delegations WHERE institution_id = $1 AND delegate_id = $2 AND status = 'active'
         UNION
         SELECT 1 FROM governance_role_assignments WHERE institution_id = $1 AND human_id = $2 AND status = 'active'
         UNION
         SELECT 1 FROM memberships WHERE city_id = $1 AND human_id = $2 AND status = 'active'`,
        [targetCityId, input.humanId],
      );
      if (!authRes.rows[0]) throw new Error('Caller is not authorized for city civic licensing');

      const existingCivic = await tx.query(
        "SELECT 1 FROM building_patent_licenses WHERE city_id = $1 AND patent_id = $2 AND status IN ('active', 'renewal_window') AND license_type = 'city_civic'",
        [targetCityId, patentSpec.patentId],
      );
      if (existingCivic.rows[0]) throw new Error('An active city-wide civic license already exists for this patent');

      if (input.buildingId) {
        const bldCheck = await tx.query<{ city_id: string }>(
          'SELECT city_id FROM buildings WHERE id = $1',
          [input.buildingId],
        );
        if (!bldCheck.rows[0]) throw new Error('Target building not found');
        if (bldCheck.rows[0].city_id !== targetCityId) throw new Error('Building does not belong to the specified city');
      }
      licenseeId = targetCityId;
    } else {
      if (!input.buildingId) {
        throw new Error('Building ID is required for private building patent license');
      }
      const bldCheck = await tx.query<{ owner_id: string }>(
        'SELECT owner_id FROM buildings WHERE id = $1',
        [input.buildingId],
      );
      if (!bldCheck.rows[0]) throw new Error('Target building not found');
      if (bldCheck.rows[0].owner_id !== input.humanId) throw new Error('Only the property owner can license this building');

      const existingPrivate = await tx.query(
        "SELECT 1 FROM building_patent_licenses WHERE building_id = $1 AND patent_id = $2 AND status IN ('active', 'renewal_window')",
        [input.buildingId, patentSpec.patentId],
      );
      if (existingPrivate.rows[0]) throw new Error('An active patent license already exists for this building');
    }

    const costCrd = isCivic
      ? (input.isPermanent ? patentSpec.cityCivicLicenseCostCrd * 3 : patentSpec.cityCivicLicenseCostCrd)
      : patentSpec.privateLicenseCostCrd;
    const termDays = input.isPermanent ? 36500 : patentSpec.termDays;
    const dailyRoyalty = input.isPermanent ? 0 : patentSpec.privateDailyRoyaltyCrd;

    const creditCostCents = BigInt(Math.round(costCrd * 100));
    const licenseId = `LIC-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    if (isCivic) {
      const cityAccount = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE account_id = $1 FOR UPDATE",
        [`account-city-${input.cityId}`],
      );
      if (!cityAccount.rows[0] || moneyToCents(cityAccount.rows[0].balance) < creditCostCents) {
        throw new Error(`Insufficient city treasury for civic patent license (Requires ${costCrd} CRD)`);
      }

      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: cityAccount.rows[0].account_id,
        creditAccount: `account-corporation-${patentSpec.owningCorporationId}`,
        amount: centsToMoney(creditCostCents),
        reasonType: 'patent_license_purchase',
        reasonId: licenseId,
        ruleVersion: 'patent-licensing-v1',
        correlationId: input.correlationId,
      });
    } else {
      const account = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [input.humanId],
      );
      if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
        throw new Error(`Insufficient Credits for patent license (Requires ${costCrd} CRD)`);
      }

      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: account.rows[0].account_id,
        creditAccount: `account-corporation-${patentSpec.owningCorporationId}`,
        amount: centsToMoney(creditCostCents),
        reasonType: 'patent_license_purchase',
        reasonId: licenseId,
        ruleVersion: 'patent-licensing-v1',
        correlationId: input.correlationId,
      });
    }

    await tx.query(
      `INSERT INTO building_patent_licenses (
        id, patent_id, patent_name, license_type, licensee_id,
        licensor_corporation_id, building_id, city_id, is_permanent,
        granted_game_day, expiry_game_day, royalty_per_day_crd, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'active')`,
      [
        licenseId,
        patentSpec.patentId,
        patentSpec.patentName,
        input.licenseType,
        licenseeId,
        patentSpec.owningCorporationId,
        input.buildingId ?? null,
        input.cityId ?? null,
        input.isPermanent ?? false,
        day,
        day + termDays,
        dailyRoyalty,
      ],
    );

    if (input.buildingId) {
      await tx.query(
        "UPDATE buildings SET patent_license_status = 'active', required_patent_id = $1 WHERE id = $2",
        [patentSpec.patentId, input.buildingId],
      );
    }

    const res = await tx.query('SELECT * FROM building_patent_licenses WHERE id = $1', [licenseId]);
    return { ok: true, license: res.rows[0], correlationId: input.correlationId };
  });
}

export async function renewBuildingPatentLicense(
  repository: PostgresRepository,
  input: {
    humanId: string;
    licenseId: string;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>(
      "SELECT reason_id FROM ledger_entries WHERE reason_type = 'patent_license_renewal' AND correlation_id = $1",
      [input.correlationId],
    );
    if (prior.rows[0]) {
      const existing = await tx.query('SELECT * FROM building_patent_licenses WHERE id = $1', [input.licenseId]);
      return { ok: true, alreadyProcessed: true, license: existing.rows[0], correlationId: input.correlationId };
    }

    const licRes = await tx.query<{
      id: string;
      patent_id: string;
      license_type: string;
      licensee_id: string;
      licensor_corporation_id: string;
      building_id: string | null;
      city_id: string | null;
      is_permanent: boolean;
      expiry_game_day: string;
    }>('SELECT * FROM building_patent_licenses WHERE id = $1 FOR UPDATE', [input.licenseId]);
    const lic = licRes.rows[0];
    if (!lic) throw new Error('Patent license not found');
    if (lic.is_permanent) throw new Error('Permanent licenses do not require renewal');

    const isCivic = lic.license_type === 'city_civic';
    if (isCivic) {
      const mem = await tx.query(
        "SELECT 1 FROM memberships WHERE city_id = $1 AND human_id = $2 AND status = 'active'",
        [lic.city_id, input.humanId],
      );
      if (!mem.rows[0]) throw new Error('Caller is not authorized to renew city license');
    } else {
      if (lic.licensee_id !== input.humanId) throw new Error('Unauthorized');
    }

    const patentSpec = findPatentSpecInCatalog(lic.patent_id);
    const costCrd = isCivic
      ? (patentSpec ? patentSpec.cityCivicLicenseCostCrd : 8000)
      : (patentSpec ? patentSpec.privateLicenseCostCrd : 5000);
    const termDays = patentSpec ? patentSpec.termDays : 30;
    const creditCostCents = BigInt(Math.round(costCrd * 100));

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    if (isCivic) {
      const cityAccount = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE account_id = $1 FOR UPDATE",
        [`account-city-${lic.city_id}`],
      );
      if (!cityAccount.rows[0] || moneyToCents(cityAccount.rows[0].balance) < creditCostCents) {
        throw new Error(`Insufficient city treasury for license renewal (Requires ${costCrd} CRD)`);
      }

      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: cityAccount.rows[0].account_id,
        creditAccount: `account-corporation-${lic.licensor_corporation_id}`,
        amount: centsToMoney(creditCostCents),
        reasonType: 'patent_license_renewal',
        reasonId: lic.id,
        ruleVersion: 'patent-licensing-v1',
        correlationId: input.correlationId,
      });
    } else {
      const account = await tx.query<{ account_id: string; balance: string }>(
        "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
        [input.humanId],
      );
      if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
        throw new Error(`Insufficient Credits for license renewal (Requires ${costCrd} CRD)`);
      }

      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(),
        gameDay: day,
        debitAccount: account.rows[0].account_id,
        creditAccount: `account-corporation-${lic.licensor_corporation_id}`,
        amount: centsToMoney(creditCostCents),
        reasonType: 'patent_license_renewal',
        reasonId: lic.id,
        ruleVersion: 'patent-licensing-v1',
        correlationId: input.correlationId,
      });
    }

    const newExpiry = Math.max(day, Number(lic.expiry_game_day)) + termDays;
    await tx.query(
      "UPDATE building_patent_licenses SET expiry_game_day = $1, status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id = $2",
      [newExpiry, lic.id],
    );

    if (lic.building_id) {
      await tx.query(
        "UPDATE buildings SET patent_license_status = 'active' WHERE id = $1",
        [lic.building_id],
      );
    }

    const updated = await tx.query('SELECT * FROM building_patent_licenses WHERE id = $1', [lic.id]);
    return { ok: true, license: updated.rows[0], correlationId: input.correlationId };
  });
}


