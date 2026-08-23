import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { BUILDING_CATALOG } from './real-estate-catalog.ts';
import { toNanoMarkup } from './nano-markup.ts';

export async function purchaseBuilding(
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
    if (spec.category === 'municipal_megaproject') {
      throw new Error('Municipal megaprojects must be procured via Democratic City Referendum');
    }

    const membership = await tx.query<{ city_id: string | null; corporation_id: string | null }>(
      'SELECT city_id, corporation_id FROM memberships WHERE human_id = $1',
      [input.ownerId],
    );
    const citizenCityId = membership.rows[0]?.city_id ?? input.cityId;

    // Check Credits
    const creditCostCents = BigInt(Math.round(spec.baseCreditCost * 100));
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.ownerId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Insufficient Credits for building acquisition (Requires ${spec.baseCreditCost} CRD)`);
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
      ruleVersion: 'real-estate-v1',
      correlationId: input.correlationId,
    });

    // Deduct Materials
    await tx.query(
      "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material'",
      [materialCost, input.ownerId],
    );

    // Insert Building
    await tx.query(
      `INSERT INTO buildings (
        id, city_id, owner_id, ownership_type, business_id,
        building_type, name, tier, condition, max_staff_slots,
        upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
        base_revenue_crd, status, created_game_day
      ) VALUES ($1, $2, $3, 'private', $4, $5, $6, $7, 100, $8, $9, $10, $11, $12, $13, $14, 'active', $15)`,
      [
        buildingId,
        citizenCityId,
        input.ownerId,
        input.businessId ?? null,
        input.buildingType,
        input.name.trim() || spec.name,
        spec.tier,
        spec.maxStaffSlots,
        spec.upkeepEnergy,
        spec.upkeepFood,
        spec.upkeepMaterials,
        spec.upkeepComponents,
        spec.upkeepCompute,
        spec.baseDailyRevenueCrd,
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
      max_staff_slots: number;
      base_revenue_crd: string;
      status: string;
    }>('SELECT * FROM buildings WHERE id = $1 FOR UPDATE', [input.buildingId]);
    const bld = bldRes.rows[0];
    if (!bld) throw new Error('Building not found');
    if (bld.owner_id !== input.humanId) throw new Error('Only the property owner can upgrade this facility');
    if (bld.tier >= 5) throw new Error('Building is already at maximum infrastructure tier (Tier 5)');

    const nextTier = bld.tier + 1;
    const upgradeCreditCost = 4500 * nextTier;
    const upgradeCompCost = 20 * nextTier;

    const creditCostCents = BigInt(upgradeCreditCost * 100);
    const account = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [input.humanId],
    );
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCostCents) {
      throw new Error(`Upgrade requires ${upgradeCreditCost} Credits`);
    }

    const compBal = await tx.query<{ amount: string }>(
      "SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE",
      [input.humanId],
    );
    if (Number(compBal.rows[0]?.amount ?? 0) < upgradeCompCost) {
      throw new Error(`Upgrade requires ${upgradeCompCost} Components`);
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
      ruleVersion: 'real-estate-v1',
      correlationId: input.correlationId,
    });

    await tx.query(
      "UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components'",
      [upgradeCompCost, input.humanId],
    );

    const newSlots = bld.max_staff_slots + 4;
    const newRevenue = Number(bld.base_revenue_crd) * 1.35;

    await tx.query(
      `UPDATE buildings SET
        tier = $1,
        max_staff_slots = $2,
        base_revenue_crd = $3,
        condition = LEAST(100, condition + 15),
        updated_at = CURRENT_TIMESTAMP
      WHERE id = $4`,
      [nextTier, newSlots, newRevenue, bld.id],
    );

    const updated = await tx.query('SELECT * FROM buildings WHERE id = $1', [bld.id]);
    return { ok: true, building: updated.rows[0], correlationId: input.correlationId };
  });
}

export async function assignBuildingStaff(
  repository: PostgresRepository,
  input: {
    humanId: string;
    buildingId: string;
    staffType: 'machine' | 'employee';
    machineId?: string;
    employeeId?: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const bld = await tx.query<{ id: string; owner_id: string; max_staff_slots: number }>(
      'SELECT id, owner_id, max_staff_slots FROM buildings WHERE id = $1 FOR UPDATE',
      [input.buildingId],
    );
    if (!bld.rows[0]) throw new Error('Building not found');
    if (bld.rows[0].owner_id !== input.humanId) throw new Error('Unauthorized');

    const currentStaffCount = await tx.query<{ count: string }>(
      "SELECT COUNT(*)::integer AS count FROM building_staff_assignments WHERE building_id = $1 AND status = 'active'",
      [input.buildingId],
    );
    if (Number(currentStaffCount.rows[0]?.count ?? 0) >= bld.rows[0].max_staff_slots) {
      throw new Error('Building staff capacity is full. Upgrade the building tier to add more slots.');
    }

    if (input.staffType === 'machine') {
      if (!input.machineId) throw new Error('machineId is required');
      const machine = await tx.query<{ id: string; owner_id: string }>(
        'SELECT id, owner_id FROM machines WHERE id = $1',
        [input.machineId],
      );
      if (!machine.rows[0] || machine.rows[0].owner_id !== input.humanId) {
        throw new Error('You do not own this machine');
      }
      const existing = await tx.query(
        "SELECT id FROM building_staff_assignments WHERE machine_id = $1 AND status = 'active'",
        [input.machineId],
      );
      if (existing.rows[0]) throw new Error('Machine is already assigned to a facility');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);
    const assignId = `STF-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    await tx.query(
      `INSERT INTO building_staff_assignments (id, building_id, staff_type, machine_id, employee_id, assigned_by, assigned_game_day)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [assignId, input.buildingId, input.staffType, input.machineId ?? null, input.employeeId ?? null, input.humanId, day],
    );

    return { ok: true, assignmentId: assignId };
  });
}

export async function registerMunicipalLabor(
  repository: PostgresRepository,
  input: { humanId: string; machineId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const member = await tx.query<{ city_id: string | null }>(
      'SELECT city_id FROM memberships WHERE human_id = $1',
      [input.humanId],
    );
    const cityId = member.rows[0]?.city_id;
    if (!cityId) throw new Error('You must belong to a City to participate in the Municipal Labor Pool');

    const machine = await tx.query<{ id: string; owner_id: string; condition: string }>(
      'SELECT id, owner_id, condition FROM machines WHERE id = $1',
      [input.machineId],
    );
    if (!machine.rows[0] || machine.rows[0].owner_id !== input.humanId) {
      throw new Error('You do not own this machine');
    }
    if (Number(machine.rows[0].condition) < 30) {
      throw new Error('Machine condition is too degraded for municipal certification (<30% condition)');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);
    const poolId = `MLP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;

    await tx.query(
      `INSERT INTO municipal_labor_pool (id, city_id, human_id, machine_id, registered_game_day, status)
       VALUES ($1, $2, $3, $4, $5, 'active')
       ON CONFLICT (city_id, machine_id) DO UPDATE SET status = 'active', updated_at = CURRENT_TIMESTAMP`,
      [poolId, cityId, input.humanId, input.machineId, day],
    );

    return { ok: true, cityId, machineId: input.machineId, status: 'active' };
  });
}

export async function withdrawMunicipalLabor(
  repository: PostgresRepository,
  input: { humanId: string; machineId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await tx.query(
      "UPDATE municipal_labor_pool SET status = 'withdrawn', updated_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND machine_id = $2",
      [input.humanId, input.machineId],
    );
    return { ok: true, machineId: input.machineId, status: 'withdrawn' };
  });
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
