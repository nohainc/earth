import type { PostgresRepository } from './repository.ts';
import { quoteCapacityChange, type CorporationCapacity, type HouseCapacity } from './v5-capacity.ts';
import { calculateProgressiveCharge } from './v5-progressive.ts';

// @mutation-boundary atomic-sql
// @mutation-boundary read-only
// Capacity quotes are read-only projections; callers own the surrounding mutation transaction.

export async function getActiveV5StandardCapacity(repository: PostgresRepository, gameDay?: number): Promise<{ standardTerritoryCapacity: bigint; earthBaseRate: bigint; houseScheduleId: string; corporationScheduleId: string; policyVersion: number; gameDay: number }> {
  const day = gameDay ?? Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
  const snapshot = (await repository.query<{ id: string; rules_json: Record<string, unknown> }>(`SELECT id, rules_json
      FROM resolved_constitution_snapshots_v5
     WHERE authority_type = 'EARTH' AND authority_id = 'EARTH' AND game_day = $1`, [day])).rows[0];
  const snapshotRules = snapshot?.rules_json ?? {};
  if (snapshot && snapshotRules['EARTH.CAPACITY.STANDARD'] !== undefined && snapshotRules['EARTH.CAPACITY.BASE_RATE'] !== undefined && snapshotRules['EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE'] !== undefined && snapshotRules['EARTH.CAPACITY.PROGRESSIVE_SCHEDULE'] !== undefined) {
    return {
      standardTerritoryCapacity: BigInt(String(snapshotRules['EARTH.CAPACITY.STANDARD'])),
      earthBaseRate: BigInt(String(snapshotRules['EARTH.CAPACITY.BASE_RATE'])),
      houseScheduleId: String(snapshotRules['EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE']),
      corporationScheduleId: String(snapshotRules['EARTH.CAPACITY.PROGRESSIVE_SCHEDULE']),
      policyVersion: 0,
      gameDay: day,
    };
  }
  const policy = (await repository.query<{ standard_territory_capacity_units: string; earth_base_capacity_rate_units: string; earth_corporation_schedule_id: string; earth_house_schedule_id: string; version: number }>(`SELECT standard_territory_capacity_units::TEXT, earth_base_capacity_rate_units::TEXT, earth_corporation_schedule_id, earth_house_schedule_id, version
    FROM v5_capacity_policy_versions
    WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
      AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day])).rows[0];
  if (!policy) throw new Error('No active V5 capacity policy is available');
  return {
    standardTerritoryCapacity: BigInt(policy.standard_territory_capacity_units),
    earthBaseRate: BigInt(policy.earth_base_capacity_rate_units),
    houseScheduleId: policy.earth_house_schedule_id,
    corporationScheduleId: policy.earth_corporation_schedule_id,
    policyVersion: policy.version,
    gameDay: day,
  };
}

export async function getV5HouseCapacity(repository: PostgresRepository, houseId: string): Promise<HouseCapacity & { generatedFrom: string }> {
  const house = (await repository.query<{ corporation_id: string | null; residential_units: string; building_units: string; total_units: string }>(`SELECT corporation_id,
      residential_capacity_units::TEXT AS residential_units,
      productive_capacity_units::TEXT AS building_units,
      total_capacity_units::TEXT AS total_units
    FROM v5_house_settlement_profiles WHERE house_id = $1`, [houseId])).rows[0];
  if (!house) throw new Error('House not found');
  const capacity: HouseCapacity = { houseId, corporationId: house.corporation_id, residentialUnits: BigInt(house.residential_units), buildingUnits: BigInt(house.building_units), totalUnits: BigInt(house.total_units) };
  const [pricing, delinquency] = await Promise.all([
    quoteV5HouseCapacityChange(repository, houseId, 1n),
    repository.query(`SELECT status, arrears_since_game_day, consecutive_missed_days, last_assessed_game_day FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [houseId]),
  ]);
  return { ...capacity, pricing, delinquency: delinquency.rows[0] ?? { status: 'CURRENT', arrears_since_game_day: null, consecutive_missed_days: 0, last_assessed_game_day: null }, generatedFrom: 'postgres-canonical-facts-v5' };
}

/** Quote a House footprint change using the active Corporation policy. */
export async function quoteV5HouseCapacityChange(repository: PostgresRepository, houseId: string, delta: bigint, gameDay?: number): Promise<Record<string, unknown> | null> {
  const house = (await repository.query<{ corporation_id: string | null; total_units: string }>(`SELECT corporation_id, total_capacity_units::TEXT AS total_units
    FROM v5_house_settlement_profiles WHERE house_id = $1`, [houseId])).rows[0];
  const day = gameDay ?? Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
  const globalPolicy = await getActiveV5StandardCapacity(repository, day);
  const corporationSnapshot = house?.corporation_id ? (await repository.query<{ rules_json: Record<string, unknown> }>(`SELECT rules_json FROM resolved_constitution_snapshots_v5 WHERE authority_type = 'CORPORATION' AND authority_id = $1 AND game_day = $2`, [house.corporation_id, day])).rows[0] : undefined;
  const policy = house?.corporation_id && corporationSnapshot?.rules_json?.['CORPORATION.HOUSE_CAPACITY.BASE_RATE'] !== undefined
    ? { rate: String(corporationSnapshot.rules_json['CORPORATION.HOUSE_CAPACITY.BASE_RATE']), schedule_id: globalPolicy.houseScheduleId, version: globalPolicy.policyVersion }
    : house?.corporation_id ? (await repository.query<{ rate: string; schedule_id: string; version: number }>(`SELECT house_base_capacity_rate_units::TEXT AS rate, house_schedule_id, version
    FROM corporation_capacity_policy_versions WHERE corporation_id = $1 AND status = 'ACTIVE'
      AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [house.corporation_id, day])).rows[0] : globalPolicy ? { rate: globalPolicy.earthBaseRate.toString(), schedule_id: globalPolicy.houseScheduleId, version: globalPolicy.policyVersion } : null;
  if (policy?.schedule_id === '') {
    const legacy = (await repository.query<{ schedule_id: string; version: number }>(`SELECT house_schedule_id AS schedule_id, version FROM corporation_capacity_policy_versions WHERE corporation_id = $1 AND status = 'ACTIVE' AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2) ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [house?.corporation_id, day])).rows[0];
    if (!legacy) return { available: false, reason: 'Corporation has no active V5 capacity policy', corporationId: house?.corporation_id ?? null };
    policy.schedule_id = legacy.schedule_id; policy.version = legacy.version;
  }
  if (!policy) return { available: false, reason: house?.corporation_id ? 'Corporation has no active V5 capacity policy' : 'No active EARTH capacity policy', corporationId: house?.corporation_id ?? null };
  const currentUnits = BigInt(house.total_units);
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [policy.schedule_id])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: currentUnits, delta, baseRate: BigInt(policy.rate), brackets });
  return { available: true, corporationId: house.corporation_id, gameDay: day, baseRateVersion: Number(policy.version), scheduleId: policy.schedule_id, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
}

export async function getV5CorporationCapacity(repository: PostgresRepository, corporationId: string, standardTerritoryCapacity: bigint): Promise<CorporationCapacity & { generatedFrom: string }> {
  if (standardTerritoryCapacity <= 0n) throw new Error('Standard Territory capacity must be positive');
  const profile = (await repository.query<{ member_count: string; residential: string; productive: string; public_units: string; total: string }>(`SELECT active_member_count::TEXT AS member_count,
      member_residential_capacity_units::TEXT AS residential,
      member_productive_capacity_units::TEXT AS productive,
      public_capacity_units::TEXT AS public_units,
      total_occupied_capacity_units::TEXT AS total
    FROM v5_corporation_settlement_profiles WHERE corporation_id = $1`, [corporationId])).rows[0];
  if (!profile) throw new Error('Corporation settlement profile not found');
  const total = BigInt(profile.total);
  const required = total === 0n ? 0n : (total + standardTerritoryCapacity - 1n) / standardTerritoryCapacity;
  return { corporationId, memberCount: BigInt(profile.member_count), residentialUnits: BigInt(profile.residential), privateBuildingUnits: BigInt(profile.productive), publicBuildingUnits: BigInt(profile.public_units), totalOccupiedUnits: total, standardTerritoryCapacity, requiredTerritoryUnits: required, utilizationNumerator: total, utilizationDenominator: standardTerritoryCapacity * required, generatedFrom: 'postgres-v5-structural-settlement-profile' };
}

/** Returns the Earth-wide pooled-capacity read model, including independent Houses. */
export async function getV5EarthCapacity(repository: PostgresRepository, gameDay?: number): Promise<Record<string, unknown>> {
  const policy = await getActiveV5StandardCapacity(repository, gameDay);
  const [houses, corporations] = await Promise.all([
    repository.query<{ house_count: string; independent_count: string; occupied_units: string }>(
      `SELECT COUNT(*)::TEXT AS house_count,
              COUNT(*) FILTER (WHERE corporation_id IS NULL)::TEXT AS independent_count,
              COALESCE(SUM(total_capacity_units), 0)::TEXT AS occupied_units
         FROM v5_house_settlement_profiles p
         JOIN houses h ON h.id = p.house_id AND h.status = 'ACTIVE'`,
    ),
    repository.query<{ corporation_count: string; occupied_units: string; required_units: string }>(
      `SELECT COUNT(*)::TEXT AS corporation_count,
              COALESCE(SUM(total_occupied_capacity_units), 0)::TEXT AS occupied_units,
              COALESCE(SUM(required_territory_units), 0)::TEXT AS required_units
         FROM corporation_capacity_state_v5 s
         JOIN corporations c ON c.id = s.corporation_id AND c.status = 'ACTIVE'
        WHERE s.game_day = $1`,
      [policy.gameDay],
    ),
  ]);
  const house = houses.rows[0];
  const corporation = corporations.rows[0];
  const independentUnits = BigInt(house?.occupied_units ?? '0');
  const corporationUnits = BigInt(corporation?.occupied_units ?? '0');
  return {
    gameDay: policy.gameDay,
    standardTerritoryCapacity: policy.standardTerritoryCapacity.toString(),
    earthBaseRate: policy.earthBaseRate.toString(),
    activeHouseCount: Number(house?.house_count ?? 0),
    independentHouseCount: Number(house?.independent_count ?? 0),
    independentOccupiedUnits: independentUnits.toString(),
    corporationCount: Number(corporation?.corporation_count ?? 0),
    corporationOccupiedUnits: corporationUnits.toString(),
    totalOccupiedUnits: (independentUnits + corporationUnits).toString(),
    requiredTerritoryUnits: BigInt(corporation?.required_units ?? '0').toString(),
    generatedFrom: 'postgres-v5-structural-settlement-profile',
  };
}

/** Quote a Corporation public-footprint change against the EARTH rent policy. */
export async function quoteV5CorporationCapacityChange(repository: PostgresRepository, corporationId: string, delta: bigint, gameDay?: number): Promise<Record<string, unknown>> {
  const policy = await getActiveV5StandardCapacity(repository, gameDay);
  const corporation = await getV5CorporationCapacity(repository, corporationId, policy.standardTerritoryCapacity);
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [policy.corporationScheduleId])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: corporation.totalOccupiedUnits, delta, baseRate: policy.earthBaseRate, brackets });
  return { available: true, corporationId, gameDay: policy.gameDay, baseRateVersion: Number(policy.policyVersion), scheduleId: policy.corporationScheduleId, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
}
