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
  await repository.query(
    'SELECT * FROM earth_rebuild_settlement_profile($1, $2)',
    [ownerId, gameDay],
  );
}

export async function catchupOwnerSettlement(
  repository: PostgresRepository,
  ownerId: string,
  targetDay?: number,
): Promise<{ ownerId: string; elapsedDays: number; lastSettledDay: number; settled: boolean }> {
  const res = await repository.query<{
    owner_id: string;
    elapsed_days: number;
    last_settled_day: string;
    settled: boolean;
  }>('SELECT * FROM earth_catchup_owner_settlement($1, $2)', [ownerId, targetDay ?? null]);
  const row = res.rows[0];
  return {
    ownerId: row?.owner_id ?? ownerId,
    elapsedDays: Number(row?.elapsed_days ?? 0),
    lastSettledDay: Number(row?.last_settled_day ?? 1),
    settled: Boolean(row?.settled),
  };
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
         'credits', credits_delta * GREATEST(1, $1 - last_settled_game_day),
         'energy', energy_delta * GREATEST(1, $1 - last_settled_game_day),
         'food', food_delta * GREATEST(1, $1 - last_settled_game_day),
         'materials', materials_delta * GREATEST(1, $1 - last_settled_game_day),
         'components', components_delta * GREATEST(1, $1 - last_settled_game_day),
         'compute', compute_delta * GREATEST(1, $1 - last_settled_game_day))
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
  const result = await repository.query<{ applied_profiles: string }>(
    'SELECT applied_profiles FROM apply_prepared_daily_resource_profiles($1)',
    [gameDay],
  );
  return Number(result.rows[0]?.applied_profiles ?? 0);
}

export async function markDailySettlementProfileDirty(repository: PostgresRepository, ownerId: string): Promise<void> {
  await repository.query("UPDATE daily_settlement_profiles SET status = 'dirty', updated_at = CURRENT_TIMESTAMP WHERE owner_id = $1", [ownerId]);
}
