import type { PostgresRepository } from './repository.ts';
import { aggregateCorporationCapacity, calculateHouseCapacity, quoteCapacityChange, type CapacityBuilding, type CorporationCapacity, type HouseCapacity } from './v5-capacity.ts';
import { calculateProgressiveCharge } from './v5-progressive.ts';

// @mutation-boundary atomic-sql
// @mutation-boundary read-only
// Capacity quotes are read-only projections; callers own the surrounding mutation transaction.

export async function getActiveV5StandardCapacity(repository: PostgresRepository, gameDay?: number): Promise<{ standardTerritoryCapacity: bigint; policyVersion: number; gameDay: number }> {
  const day = gameDay ?? Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
  const policy = (await repository.query<{ standard_territory_capacity_units: string; version: number }>(`SELECT standard_territory_capacity_units::TEXT, version
    FROM v5_capacity_policy_versions
    WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
      AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day])).rows[0];
  if (!policy) throw new Error('No active V5 capacity policy is available');
  return { standardTerritoryCapacity: BigInt(policy.standard_territory_capacity_units), policyVersion: policy.version, gameDay: day };
}

function mapBuilding(row: { id: string; footprint: string; status: string }): CapacityBuilding {
  return { id: row.id, footprint: BigInt(row.footprint), billable: row.status === 'ACTIVE' };
}

export async function getV5HouseCapacity(repository: PostgresRepository, houseId: string): Promise<HouseCapacity & { generatedFrom: string }> {
  const house = (await repository.query<{ id: string; corporation_id: string | null }>(`SELECT h.id, ha.corporation_id
    FROM houses h LEFT JOIN house_affiliations ha ON ha.house_id = h.id AND ha.status = 'ACTIVE'
    WHERE h.id = $1`, [houseId])).rows[0];
  if (!house) throw new Error('House not found');
  const buildings = await repository.query<{ id: string; footprint: string; status: string }>(`SELECT b.id, bc.slot_footprint::TEXT AS footprint, b.status
    FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
    JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE' AND o.id = $1
    WHERE b.status <> 'DESTROYED'`, [houseId]);
  const capacity = calculateHouseCapacity({ houseId, corporationId: house.corporation_id, activeAffiliation: house.corporation_id !== null, buildings: buildings.rows.map(mapBuilding) });
  const [pricing, delinquency] = await Promise.all([
    quoteV5HouseCapacityChange(repository, houseId, 1n),
    repository.query(`SELECT status, arrears_since_game_day, consecutive_missed_days, last_assessed_game_day FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [houseId]),
  ]);
  return { ...capacity, pricing, delinquency: delinquency.rows[0] ?? { status: 'CURRENT', arrears_since_game_day: null, consecutive_missed_days: 0, last_assessed_game_day: null }, generatedFrom: 'postgres-canonical-facts-v5' };
}

/** Quote a House footprint change using the active Corporation policy. */
export async function quoteV5HouseCapacityChange(repository: PostgresRepository, houseId: string, delta: bigint, gameDay?: number): Promise<Record<string, unknown> | null> {
  const house = (await repository.query<{ corporation_id: string | null; economic_id: string }>(`SELECT ha.corporation_id, o.economic_id
    FROM houses h JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE'
      LEFT JOIN house_affiliations ha ON ha.house_id = h.id AND ha.status = 'ACTIVE'
    WHERE h.id = $1`, [houseId])).rows[0];
  if (!house?.corporation_id) return null;
  const day = gameDay ?? Number((await repository.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
  const policy = (await repository.query<{ rate: string; schedule_id: string; version: number }>(`SELECT house_base_capacity_rate_units::TEXT AS rate, house_schedule_id, version
    FROM corporation_capacity_policy_versions WHERE corporation_id = $1 AND status = 'ACTIVE'
      AND effective_from_game_day <= $2 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
    ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [house.corporation_id, day])).rows[0];
  if (!policy) return { available: false, reason: 'Corporation has no active V5 capacity policy', corporationId: house.corporation_id };
  const currentUnits = BigInt((await repository.query<{ units: string }>(`SELECT (1 + COALESCE(SUM(bc.slot_footprint) FILTER (WHERE b.status = 'ACTIVE'),0))::TEXT AS units
    FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id WHERE b.owner_economic_id = $1 AND b.status <> 'DESTROYED'`, [house.economic_id])).rows[0]?.units ?? '1');
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [policy.schedule_id])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: currentUnits, delta, baseRate: BigInt(policy.rate), brackets });
  return { available: true, corporationId: house.corporation_id, gameDay: day, baseRateVersion: Number(policy.version), scheduleId: policy.schedule_id, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
}

export async function getV5CorporationCapacity(repository: PostgresRepository, corporationId: string, standardTerritoryCapacity: bigint): Promise<CorporationCapacity & { generatedFrom: string }> {
  if (standardTerritoryCapacity <= 0n) throw new Error('Standard Territory capacity must be positive');
  const houses = await repository.query<{ house_id: string; corporation_id: string }>(`SELECT ha.house_id, ha.corporation_id
    FROM house_affiliations ha WHERE ha.corporation_id = $1 AND ha.status = 'ACTIVE' ORDER BY ha.house_id`, [corporationId]);
  const houseCapacities = await Promise.all(houses.rows.map(async (house) => {
    const buildings = await repository.query<{ id: string; footprint: string; status: string }>(`SELECT b.id, bc.slot_footprint::TEXT AS footprint, b.status
      FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
      JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE' AND o.id = $1
      WHERE b.status <> 'DESTROYED'`, [house.house_id]);
    return calculateHouseCapacity({ houseId: house.house_id, corporationId: house.corporation_id, activeAffiliation: true, buildings: buildings.rows.map(mapBuilding) });
  }));
  const publicUnits = (await repository.query<{ units: string }>(`SELECT COALESCE(SUM(bc.slot_footprint), 0)::TEXT AS units
    FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
    JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.owner_type = 'CORPORATION' AND o.id = $1
    WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'`, [corporationId])).rows[0]?.units ?? '0';
  return { ...aggregateCorporationCapacity({ corporationId, houses: houseCapacities, publicBuildingUnits: BigInt(publicUnits), standardTerritoryCapacity }), generatedFrom: 'postgres-canonical-facts-v5' };
}

/** Quote a Corporation public-footprint change against the EARTH rent policy. */
export async function quoteV5CorporationCapacityChange(repository: PostgresRepository, corporationId: string, delta: bigint, gameDay?: number): Promise<Record<string, unknown>> {
  const policy = await getActiveV5StandardCapacity(repository, gameDay);
  const corporation = await getV5CorporationCapacity(repository, corporationId, policy.standardTerritoryCapacity);
  const pricing = (await repository.query<{ base_rate: string; schedule_id: string; version: number }>(`SELECT earth_base_capacity_rate_units::TEXT AS base_rate, earth_corporation_schedule_id AS schedule_id, version FROM v5_capacity_policy_versions WHERE status = 'ACTIVE' AND effective_from_game_day <= $1 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1) ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [policy.gameDay])).rows[0];
  if (!pricing) return { available: false, reason: 'No active EARTH capacity policy is available', corporationId };
  const brackets = (await repository.query<{ ordinal: number; lower: string; upper: string | null; numerator: string; denominator: string }>(`SELECT ordinal, lower_bound_units::TEXT AS lower, upper_bound_units::TEXT AS upper, marginal_multiplier_numerator::TEXT AS numerator, marginal_multiplier_denominator::TEXT AS denominator FROM progressive_policy_brackets WHERE schedule_id = $1 ORDER BY ordinal`, [pricing.schedule_id])).rows.map((row) => ({ ordinal: Number(row.ordinal), lowerBound: BigInt(row.lower), upperBound: row.upper === null ? null : BigInt(row.upper), multiplierNumerator: BigInt(row.numerator), multiplierDenominator: BigInt(row.denominator) }));
  const quote = quoteCapacityChange({ currentUsage: corporation.totalOccupiedUnits, delta, baseRate: BigInt(pricing.base_rate), brackets });
  return { available: true, corporationId, gameDay: policy.gameDay, baseRateVersion: Number(pricing.version), scheduleId: pricing.schedule_id, currentUsage: quote.currentUsage.toString(), usageDelta: quote.delta.toString(), afterUsage: quote.afterUsage.toString(), currentChargeUnits: quote.currentCharge.totalCharge.toString(), afterChargeUnits: quote.afterCharge.totalCharge.toString(), incrementalChargeUnits: quote.incrementalCharge.toString(), currentBracket: quote.currentCharge.currentBracket, resultingBracket: quote.afterCharge.currentBracket };
}
