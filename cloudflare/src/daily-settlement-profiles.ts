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
    'SELECT * FROM earth_rebuild_settlement_profile($1::text, $2::bigint)',
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
  }>('SELECT * FROM earth_catchup_owner_settlement($1::text, $2::bigint)', [ownerId, targetDay ?? null]);
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

/** Applies the prepared daily profile as real gameplay. Credits and resources
 * are posted atomically by earth_catchup_owner_settlement, with an idempotent
 * applied run and ledger correlation for every owner/day. */
export async function applyPreparedSettlementProfiles(repository: PostgresRepository, gameDay: number): Promise<number> {
  const dueOwners = await repository.query<{ owner_id: string }>(
    `SELECT owner_id FROM daily_settlement_profiles
     WHERE status = 'clean' AND last_settled_game_day < $1
       AND owner_kind IN ('human', 'city', 'corporation', 'earth')
       AND (credits_delta = 0 OR EXISTS (
         SELECT 1 FROM account_balances credit_account
         WHERE credit_account.owner_id = daily_settlement_profiles.owner_id
           AND credit_account.currency = 'CREDIT'
       ))`,
    [gameDay],
  );
  let appliedCount = 0;
  for (const row of dueOwners.rows) {
    const res = await repository.query<{ settled: boolean }>(
      'SELECT * FROM earth_catchup_owner_settlement($1::text, $2::bigint)',
      [row.owner_id, gameDay],
    );
    if (res.rows[0]?.settled) appliedCount++;
  }
  return appliedCount;
}

export async function markDailySettlementProfileDirty(repository: PostgresRepository, ownerId: string): Promise<void> {
  await repository.query("UPDATE daily_settlement_profiles SET status = 'dirty', updated_at = CURRENT_TIMESTAMP WHERE owner_id = $1", [ownerId]);
}
