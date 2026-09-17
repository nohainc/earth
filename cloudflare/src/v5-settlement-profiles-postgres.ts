import type { PostgresRepository } from './repository.ts';

export const V5_SETTLEMENT_PROFILE_VERSION = 'v5-structural-capacity-1';

type ProfileCount = { housesRebuilt: number; corporationsRebuilt: number };

/**
 * Rebuilds a House profile from canonical affiliation and building facts.
 * This is intentionally rebuildable: the profile is a materialized projection,
 * never the source of ownership truth.
 */
// @mutation-boundary caller-owned-transaction
export async function rebuildV5HouseSettlementProfile(
  tx: PostgresRepository,
  houseId: string,
  gameDay: number,
): Promise<{ corporationId: string | null }> {
  const affiliation = (await tx.query<{ corporation_id: string | null }>(
    `SELECT corporation_id FROM house_affiliations
      WHERE house_id = $1 AND status = 'ACTIVE'
      ORDER BY joined_game_day DESC, id DESC LIMIT 1`,
    [houseId],
  )).rows[0];
  const facts = (await tx.query<{ building_units: string; building_count: string }>(
    `SELECT COALESCE(SUM(bc.slot_footprint), 0)::TEXT AS building_units,
            COUNT(*)::TEXT AS building_count
       FROM buildings b
       JOIN building_catalog bc ON bc.id = b.catalog_id
       JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                            AND o.owner_type = 'HOUSE' AND o.id = $1
      WHERE b.status = 'ACTIVE'`,
    [houseId],
  )).rows[0] ?? { building_units: '0', building_count: '0' };
  await tx.query(
    `INSERT INTO v5_house_settlement_profiles
       (house_id, corporation_id, residential_capacity_units, productive_capacity_units,
        total_capacity_units, active_building_count, profile_version, source_game_day,
        dirty, dirty_reason)
     VALUES ($1, $2, 1, $3, 1 + $3, $4, $5, $6, FALSE, NULL)
     ON CONFLICT (house_id) DO UPDATE SET corporation_id = EXCLUDED.corporation_id,
       residential_capacity_units = EXCLUDED.residential_capacity_units,
       productive_capacity_units = EXCLUDED.productive_capacity_units,
       total_capacity_units = EXCLUDED.total_capacity_units,
       active_building_count = EXCLUDED.active_building_count,
       profile_version = EXCLUDED.profile_version,
       source_game_day = EXCLUDED.source_game_day,
       dirty = FALSE, dirty_reason = NULL, updated_at = CURRENT_TIMESTAMP`,
    [houseId, affiliation?.corporation_id ?? null, facts.building_units, Number(facts.building_count), V5_SETTLEMENT_PROFILE_VERSION, gameDay],
  );
  return { corporationId: affiliation?.corporation_id ?? null };
}

/** Rebuilds a Corporation aggregate from House profiles and public buildings. */
// @mutation-boundary caller-owned-transaction
export async function rebuildV5CorporationSettlementProfile(
  tx: PostgresRepository,
  corporationId: string,
  gameDay: number,
): Promise<void> {
  await tx.query(
    `INSERT INTO v5_corporation_settlement_profiles
       (corporation_id, active_member_count, member_residential_capacity_units,
        member_productive_capacity_units, public_capacity_units,
        total_occupied_capacity_units, active_public_building_count,
        profile_version, source_game_day, dirty, dirty_reason)
     SELECT $1,
       COUNT(hp.house_id)::INTEGER,
       COALESCE(SUM(hp.residential_capacity_units), 0),
       COALESCE(SUM(hp.productive_capacity_units), 0),
       COALESCE(public_facts.capacity_units, 0),
       COALESCE(SUM(hp.total_capacity_units), 0) + COALESCE(public_facts.capacity_units, 0),
       COALESCE(public_facts.building_count, 0)::INTEGER,
       $2, $3, FALSE, NULL
     FROM v5_house_settlement_profiles hp
     LEFT JOIN (
       SELECT COALESCE(SUM(bc.slot_footprint), 0) AS capacity_units,
              COUNT(*) AS building_count
         FROM buildings b
         JOIN building_catalog bc ON bc.id = b.catalog_id
         JOIN owner_registry o ON o.economic_id = b.owner_economic_id
                              AND o.owner_type = 'CORPORATION' AND o.id = $1
        WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'
     ) public_facts ON TRUE
    WHERE hp.corporation_id = $1
     ON CONFLICT (corporation_id) DO UPDATE SET
       active_member_count = EXCLUDED.active_member_count,
       member_residential_capacity_units = EXCLUDED.member_residential_capacity_units,
       member_productive_capacity_units = EXCLUDED.member_productive_capacity_units,
       public_capacity_units = EXCLUDED.public_capacity_units,
       total_occupied_capacity_units = EXCLUDED.total_occupied_capacity_units,
       active_public_building_count = EXCLUDED.active_public_building_count,
       profile_version = EXCLUDED.profile_version,
       source_game_day = EXCLUDED.source_game_day,
       dirty = FALSE, dirty_reason = NULL, updated_at = CURRENT_TIMESTAMP`,
    [corporationId, gameDay, V5_SETTLEMENT_PROFILE_VERSION],
  );
}

/** Refreshes one House and every affected Corporation in the same transaction. */
// @mutation-boundary caller-owned-transaction
export async function refreshV5SettlementProfilesForHouse(
  tx: PostgresRepository,
  houseId: string,
  gameDay: number,
  affectedCorporationIds: readonly string[] = [],
): Promise<void> {
  const rebuilt = await rebuildV5HouseSettlementProfile(tx, houseId, gameDay);
  const corporationIds = new Set(affectedCorporationIds);
  if (rebuilt.corporationId) corporationIds.add(rebuilt.corporationId);
  for (const corporationId of corporationIds) await rebuildV5CorporationSettlementProfile(tx, corporationId, gameDay);
}

/** Repairs missing, dirty, or version-incompatible profiles in one owner shard. */
// @mutation-boundary caller-owned-transaction
export async function rebuildV5SettlementProfilesInShard(
  tx: PostgresRepository,
  gameDay: number,
  shard: number,
  shardCount: number,
): Promise<ProfileCount> {
  const houses = (await tx.query<{ id: string }>(
    `SELECT h.id FROM houses h
      LEFT JOIN v5_house_settlement_profiles p ON p.house_id = h.id
     WHERE (p.house_id IS NULL OR p.dirty OR p.profile_version <> $1)
       AND MOD(ABS(hashtextextended(h.id, 0)), $2) = $3
     ORDER BY h.id`,
    [V5_SETTLEMENT_PROFILE_VERSION, shardCount, shard],
  )).rows;
  const corporations = new Set<string>();
  for (const house of houses) {
    const result = await rebuildV5HouseSettlementProfile(tx, house.id, gameDay);
    if (result.corporationId) corporations.add(result.corporationId);
  }
  for (const corporationId of corporations) await rebuildV5CorporationSettlementProfile(tx, corporationId, gameDay);
  return { housesRebuilt: houses.length, corporationsRebuilt: corporations.size };
}

/** Cheap O(C) daily projection pass based on repaired House profiles. */
// @mutation-boundary deterministic-settlement
export async function settleV5CorporationSettlementProfiles(
  tx: PostgresRepository,
  gameDay: number,
): Promise<ProfileCount> {
  const corporations = (await tx.query<{ id: string }>(
    "SELECT id FROM corporations WHERE status = 'ACTIVE' ORDER BY id",
  )).rows;
  for (const corporation of corporations) await rebuildV5CorporationSettlementProfile(tx, corporation.id, gameDay);
  return { housesRebuilt: 0, corporationsRebuilt: corporations.length };
}
