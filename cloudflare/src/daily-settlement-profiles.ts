import type { PostgresRepository } from './repository.ts';

type Profile = {
  owner_id: string;
  owner_kind: string;
};

/**
 * Rebuilds the stable physical-resource part of an owner's daily profile.
 * Credit revenue, dividends, market clearing, shortages and tax remain
 * dynamic settlement inputs and are deliberately not cached here.
 */
export async function rebuildDailySettlementProfile(
  repository: PostgresRepository,
  ownerId: string,
  gameDay: number,
): Promise<void> {
  const profile = await repository.query<Profile>(
    'SELECT owner_id, owner_kind FROM daily_settlement_profiles WHERE owner_id = $1 FOR UPDATE',
    [ownerId],
  );
  if (!profile.rows[0]) return;
  const isCity = profile.rows[0].owner_kind === 'city';
  const buildings = await repository.query<{
    resource_output_type: string | null; resource_output_amount: string | null;
    upkeep_energy: string; upkeep_food: string; upkeep_materials: string;
    upkeep_components: string; upkeep_compute: string; operating_policy: string | null; condition: string;
  }>(
    isCity
      ? "SELECT resource_output_type,resource_output_amount,upkeep_energy,upkeep_food,upkeep_materials,upkeep_components,upkeep_compute,operating_policy,condition FROM buildings WHERE city_id = $1 AND ownership_class = 'civic' AND status = 'active'"
      : "SELECT resource_output_type,resource_output_amount,upkeep_energy,upkeep_food,upkeep_materials,upkeep_components,upkeep_compute,operating_policy,condition FROM buildings WHERE owner_id = $1 AND ownership_class = 'private' AND status = 'active'",
    [ownerId],
  );
  const delta: Record<string, number> = { credits: 0, energy: 0, food: 0, materials: 0, components: 0, compute: 0 };
  for (const building of buildings.rows) {
    const policy = building.operating_policy ?? 'balanced';
    const outputMultiplier = policy === 'high_output' ? 1.3 : ['frugal', 'eco_reserve'].includes(policy) ? .75 : 1;
    const costMultiplier = policy === 'high_output' ? 1.4 : ['frugal', 'eco_reserve'].includes(policy) ? .7 : 1;
    const condition = Number(building.condition ?? 100);
    const efficiency = condition >= 80 ? 1 : condition >= 50 ? .75 : condition >= 20 ? .4 : .1;
    const conditionCost = condition >= 80 ? 1 : condition >= 50 ? 1.15 : condition >= 20 ? 1.4 : 2;
    const output = Number(building.resource_output_amount ?? 0) * outputMultiplier * efficiency;
    const outputType = building.resource_output_type ?? 'credits';
    if (outputType in delta) delta[outputType] += output;
    for (const resource of ['energy', 'food', 'materials', 'components', 'compute']) {
      delta[resource] -= Number(building[`upkeep_${resource}` as keyof typeof building] ?? 0) * costMultiplier * conditionCost;
    }
  }
  const fingerprint = JSON.stringify({ buildings: buildings.rows.length, delta });
  await repository.query(
    `UPDATE daily_settlement_profiles SET status = 'clean', profile_version = profile_version + 1,
      effective_game_day = $2, credits_delta = $3, energy_delta = $4, food_delta = $5,
      materials_delta = $6, components_delta = $7, compute_delta = $8, input_fingerprint = $9,
      updated_at = CURRENT_TIMESTAMP WHERE owner_id = $1`,
    [ownerId, gameDay, delta.credits, delta.energy, delta.food, delta.materials, delta.components, delta.compute, fingerprint],
  );
}

export async function rebuildDirtyDailySettlementProfiles(repository: PostgresRepository, gameDay: number): Promise<number> {
  const profiles = await repository.query<Profile>("SELECT owner_id, owner_kind FROM daily_settlement_profiles WHERE status = 'dirty' ORDER BY owner_kind, owner_id FOR UPDATE");
  for (const profile of profiles.rows) await rebuildDailySettlementProfile(repository, profile.owner_id, gameDay);
  return profiles.rows.length;
}

/**
 * Saves one immutable, idempotent snapshot per owner and game day. This is the
 * shadow executor: it exercises the exact prepared input set without changing
 * any live balance while the legacy Building engine remains authoritative.
 */
export async function recordDailySettlementProfileShadow(repository: PostgresRepository, gameDay: number): Promise<number> {
  const result = await repository.query<{ owner_id: string }>(
    `INSERT INTO daily_settlement_profile_runs
       (owner_id, game_day, profile_version, last_settled_game_day, elapsed_days, mode, expected_delta)
     SELECT owner_id, $1, profile_version, last_settled_game_day,
       GREATEST(1, $1 - last_settled_game_day), 'shadow',
       jsonb_build_object(
         'credits', credits_delta, 'energy', energy_delta, 'food', food_delta,
         'materials', materials_delta, 'components', components_delta, 'compute', compute_delta)
     FROM daily_settlement_profiles
     WHERE status = 'clean'
     ON CONFLICT (owner_id, game_day) DO NOTHING
     RETURNING owner_id`,
    [gameDay],
  );
  return result.rows.length;
}

/** Applies only normal, physical-resource deltas. Any owner that would cross
 * zero is deliberately left to the detailed legacy path for shortage handling. */
export async function applyPreparedResourceProfiles(repository: PostgresRepository, gameDay: number): Promise<number> {
  const profiles = await repository.query<{
    owner_id: string; owner_kind: string; energy_delta: string; food_delta: string;
    materials_delta: string; components_delta: string; compute_delta: string;
  }>(
    `SELECT owner_id, owner_kind, energy_delta, food_delta, materials_delta, components_delta, compute_delta
     FROM daily_settlement_profiles
     WHERE status = 'clean' AND last_settled_game_day < $1 AND owner_kind IN ('human', 'city')
     ORDER BY owner_kind, owner_id FOR UPDATE`, [gameDay],
  );
  let applied = 0;
  for (const profile of profiles.rows) {
    const delta = {
      energy: Number(profile.energy_delta), food: Number(profile.food_delta),
      materials: Number(profile.materials_delta), components: Number(profile.components_delta),
      compute: Number(profile.compute_delta),
    };
    const held = await repository.query<{ resource: string; amount: string }>(
      "SELECT resource, amount FROM resource_balances WHERE owner_id = $1 AND resource IN ('energy','food','materials','components','compute') FOR UPDATE", [profile.owner_id],
    );
    const balance = new Map(held.rows.map((row) => [row.resource, Number(row.amount)]));
    const canApply = Object.entries(delta).every(([resource, amount]) => amount >= 0 || (balance.get(resource) ?? 0) + amount >= 0);
    if (!canApply) continue;
    for (const [resource, amount] of Object.entries(delta)) {
      if (amount === 0) continue;
      await repository.query(
        `INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3)
         ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount`,
        [profile.owner_id, resource, amount],
      );
    }
    await repository.query('UPDATE daily_settlement_profiles SET last_settled_game_day = $2 WHERE owner_id = $1', [profile.owner_id, gameDay]);
    await repository.query("UPDATE daily_settlement_profile_runs SET mode = 'applied' WHERE owner_id = $1 AND game_day = $2", [profile.owner_id, gameDay]);
    applied += 1;
  }
  return applied;
}

export async function markDailySettlementProfileDirty(repository: PostgresRepository, ownerId: string): Promise<void> {
  await repository.query("UPDATE daily_settlement_profiles SET status = 'dirty', updated_at = CURRENT_TIMESTAMP WHERE owner_id = $1", [ownerId]);
}
