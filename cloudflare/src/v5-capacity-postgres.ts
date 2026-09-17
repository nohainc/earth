import type { PostgresRepository } from './repository.ts';
import { quoteCapacityChange, type CorporationCapacity, type HouseCapacity } from './v5-capacity.ts';
import { calculateProgressiveCharge } from './v5-progressive.ts';

// @mutation-boundary atomic-sql
// @mutation-boundary read-only
// Capacity quotes are read-only projections; callers own the surrounding mutation transaction.

export async function getActiveV5StandardCapacity(repository: PostgresRepository, gameDay?: number): Promise<{ standardTerritoryCapacity: bigint; earthBaseRate: bigint; houseScheduleId: string; corporationScheduleId: string; policyVersion: string; gameDay: number }> {
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
      policyVersion: snapshot.id,
      gameDay: day,
    };
  }
  throw new Error(`Canonical Earth capacity snapshot is unavailable for game day ${day}`);
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
    ? { rate: String(corporationSnapshot.rules_json['CORPORATION.HOUSE_CAPACITY.BASE_RATE']), schedule_id: globalPolicy.houseScheduleId, version: corporationSnapshot.id }
    : house?.corporation_id ? (() => { throw new Error(`Canonical Corporation capacity snapshot is unavailable for Corporation ${house.corporation_id} on game day ${day}`); })() : { rate: globalPolicy.earthBaseRate.toString(), schedule_id: globalPolicy.houseScheduleId, version: globalPolicy.policyVersion };
  const currentUnits = BigInt(house.total_units);
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [policy.schedule_id])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: currentUnits, delta, baseRate: BigInt(policy.rate), brackets });
  return { available: true, corporationId: house.corporation_id, gameDay: day, baseRateVersion: policy.version, scheduleId: policy.schedule_id, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
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
  const [houseRent, earthRent, delinquency] = await Promise.all([
    repository.query<{ assessed: string; paid: string; arrears: string; game_day: string }>(`SELECT COALESCE(SUM(assessed_units), 0)::TEXT AS assessed,
              COALESCE(SUM(paid_units), 0)::TEXT AS paid,
              COALESCE(SUM(assessed_units - paid_units), 0)::TEXT AS arrears,
              COALESCE(MAX(game_day), 0)::TEXT AS game_day
         FROM v5_capacity_obligations
        WHERE capacity_level = 'HOUSE' AND corporation_id = $1`, [corporationId]),
    repository.query<{ assessed: string; paid: string; arrears: string; game_day: string }>(`SELECT COALESCE(SUM(assessed_units), 0)::TEXT AS assessed,
              COALESCE(SUM(paid_units), 0)::TEXT AS paid,
              COALESCE(SUM(assessed_units - paid_units), 0)::TEXT AS arrears,
              COALESCE(MAX(game_day), 0)::TEXT AS game_day
         FROM v5_capacity_obligations
        WHERE capacity_level = 'CORPORATION' AND corporation_id = $1`, [corporationId]),
    repository.query<{ status: string; arrears_since_game_day: string | null; consecutive_missed_days: string; last_assessed_game_day: string | null }>(`SELECT status, arrears_since_game_day::TEXT, consecutive_missed_days::TEXT, last_assessed_game_day::TEXT
         FROM v5_capacity_delinquency_state
        WHERE subject_type = 'CORPORATION' AND subject_id = $1`, [corporationId]),
  ]);
  const houseRentRow = houseRent.rows[0] ?? { assessed: '0', paid: '0', arrears: '0', game_day: '0' };
  const earthRentRow = earthRent.rows[0] ?? { assessed: '0', paid: '0', arrears: '0', game_day: '0' };
  const housePaid = BigInt(houseRentRow.paid);
  const earthPaid = BigInt(earthRentRow.paid);
  const total = BigInt(profile.total);
  const required = total === 0n ? 0n : (total + standardTerritoryCapacity - 1n) / standardTerritoryCapacity;
  return {
    corporationId,
    memberCount: BigInt(profile.member_count),
    residentialUnits: BigInt(profile.residential),
    privateBuildingUnits: BigInt(profile.productive),
    publicBuildingUnits: BigInt(profile.public_units),
    totalOccupiedUnits: total,
    standardTerritoryCapacity,
    requiredTerritoryUnits: required,
    utilizationNumerator: total,
    utilizationDenominator: standardTerritoryCapacity * required,
    fiscal: {
      houseCapacityRevenueAssessedUnits: houseRentRow.assessed,
      houseCapacityRevenuePaidUnits: houseRentRow.paid,
      houseCapacityArrearsUnits: houseRentRow.arrears,
      earthCapacityExpenseAssessedUnits: earthRentRow.assessed,
      earthCapacityExpensePaidUnits: earthRentRow.paid,
      earthCapacityArrearsUnits: earthRentRow.arrears,
      landMarginUnits: (housePaid - earthPaid).toString(),
      assessedGameDay: Math.max(Number(houseRentRow.game_day), Number(earthRentRow.game_day)),
    },
    delinquency: delinquency.rows[0] ?? {
      status: 'CURRENT',
      arrears_since_game_day: null,
      consecutive_missed_days: '0',
      last_assessed_game_day: null,
    },
    generatedFrom: 'postgres-v5-structural-settlement-profile',
  };
}

/** Returns the Earth-wide pooled-capacity read model, including independent Houses. */
export async function getV5EarthCapacity(repository: PostgresRepository, gameDay?: number): Promise<Record<string, unknown>> {
  const policy = await getActiveV5StandardCapacity(repository, gameDay);
  const [houses, corporations, capacityRevenue, treasury, programCommitments] = await Promise.all([
    repository.query<{ house_count: string; independent_count: string; independent_occupied_units: string }>(
      `SELECT COUNT(*)::TEXT AS house_count,
              COUNT(*) FILTER (WHERE corporation_id IS NULL)::TEXT AS independent_count,
              COALESCE(SUM(total_capacity_units) FILTER (WHERE corporation_id IS NULL), 0)::TEXT AS independent_occupied_units
         FROM v5_house_settlement_profiles p
         JOIN houses h ON h.id = p.house_id AND h.status = 'ACTIVE'`,
    ),
    repository.query<{ corporation_count: string; occupied_units: string }>(
      `SELECT COUNT(*)::TEXT AS corporation_count,
              COALESCE(SUM(total_occupied_capacity_units), 0)::TEXT AS occupied_units
         FROM corporation_capacity_state_v5 s
         JOIN corporations c ON c.id = s.corporation_id AND c.status = 'ACTIVE'
        WHERE s.game_day = $1`,
      [policy.gameDay],
    ),
    repository.query<{ assessed: string; paid: string; arrears: string; game_day: string }>(
      `SELECT COALESCE(SUM(assessed_units), 0)::TEXT AS assessed,
              COALESCE(SUM(paid_units), 0)::TEXT AS paid,
              COALESCE(SUM(assessed_units - paid_units), 0)::TEXT AS arrears,
              COALESCE(MAX(game_day), 0)::TEXT AS game_day
         FROM v5_capacity_obligations
        WHERE capacity_level = 'CORPORATION'
           OR (capacity_level = 'HOUSE' AND corporation_id IS NULL)`,
    ),
    repository.query<{ account_type: string; balance_units: string }>(
      `SELECT a.account_type, COALESCE(SUM(a.balance_units), 0)::TEXT AS balance_units
         FROM economic_accounts a
         JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.id = 'EARTH'
          AND a.asset_id = 1
          AND a.account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE')
          AND a.status = 'ACTIVE'
        GROUP BY a.account_type`,
    ),
    repository.query<{ authorized: string; committed: string; spent: string }>(
      `SELECT COALESCE(SUM(authorized_units), 0)::TEXT AS authorized,
              COALESCE(SUM(committed_units), 0)::TEXT AS committed,
              COALESCE(SUM(spent_units), 0)::TEXT AS spent
         FROM institution_budget_lines
        WHERE institution_id = 'EARTH'
          AND status IN ('ACTIVE', 'OPEN', 'APPROVED')`,
    ),
  ]);
  const house = houses.rows[0];
  const corporation = corporations.rows[0];
  const revenue = capacityRevenue.rows[0] ?? { assessed: '0', paid: '0', arrears: '0', game_day: '0' };
  const earthAccounts = Object.fromEntries(treasury.rows.map((row) => [row.account_type.toLowerCase(), row.balance_units]));
  const commitments = programCommitments.rows[0] ?? { authorized: '0', committed: '0', spent: '0' };
  const independentUnits = BigInt(house?.independent_occupied_units ?? '0');
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
    requiredTerritoryUnits: (independentUnits + corporationUnits) === 0n
      ? '0'
      : ((independentUnits + corporationUnits + policy.standardTerritoryCapacity - 1n) / policy.standardTerritoryCapacity).toString(),
    fiscal: {
      capacityRevenueAssessedUnits: revenue.assessed,
      capacityRevenuePaidUnits: revenue.paid,
      capacityRevenueArrearsUnits: revenue.arrears,
      capacityRevenueAssessedGameDay: Number(revenue.game_day),
      treasuryUnits: earthAccounts.treasury ?? '0',
      operationsUnits: earthAccounts.operations ?? '0',
      reserveUnits: earthAccounts.reserve ?? '0',
      programCommitments: {
        authorizedUnits: commitments.authorized,
        committedUnits: commitments.committed,
        spentUnits: commitments.spent,
      },
    },
    generatedFrom: 'postgres-v5-structural-settlement-profile',
  };
}

/** Quote a Corporation public-footprint change against the EARTH rent policy. */
export async function quoteV5CorporationCapacityChange(repository: PostgresRepository, corporationId: string, delta: bigint, gameDay?: number): Promise<Record<string, unknown>> {
  const policy = await getActiveV5StandardCapacity(repository, gameDay);
  const corporation = await getV5CorporationCapacity(repository, corporationId, policy.standardTerritoryCapacity);
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [policy.corporationScheduleId])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: corporation.totalOccupiedUnits, delta, baseRate: policy.earthBaseRate, brackets });
  return { available: true, corporationId, gameDay: policy.gameDay, baseRateVersion: policy.policyVersion, scheduleId: policy.corporationScheduleId, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
}
