import type { PostgresRepository } from './repository.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';
import { createNotification } from './notifications-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';

async function applyOptionalSuccessionCost(tx: PostgresRepository, houseId: string, day: number): Promise<{ units: bigint; ruleVersion: string | null; transitionDays: number }> {
  const rule = await tx.query<{ id: string; value_json: unknown }>(
    `SELECT id, value_json FROM governance_rules
      WHERE institution_id = 'OUC' AND category = 'succession' AND status = 'active'
        AND effective_from_game_day <= $1
        AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
      ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`, [day],
  );
  if (!rule.rows[0]) return { units: 0n, ruleVersion: null, transitionDays: 1 };
  const value = typeof rule.rows[0].value_json === 'string'
    ? fromNanoMarkup<Record<string, unknown>>(rule.rows[0].value_json)
    : (rule.rows[0].value_json as Record<string, unknown> ?? {});
  const accounts = await tx.query<{ owner_id: string; account_id: string; balance: string }>(
    `SELECT o.id AS owner_id, a.id::TEXT AS account_id, a.balance::TEXT AS balance
       FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
      WHERE o.id = ANY($1::TEXT[]) AND a.asset_id = 1 AND a.is_default_settlement
        AND a.status = 'active' AND a.account_type IN (1, 3)
      ORDER BY o.id FOR UPDATE`, [['OUC', houseId]],
  );
  const house = accounts.rows.find((account) => account.owner_id === houseId);
  const ouc = accounts.rows.find((account) => account.owner_id === 'OUC');
  if (!house || !ouc) throw new Error('Succession cost requires House and OUC CREDIT accounts');
  const balance = BigInt(house.balance);
  const fixedUnits = BigInt(String(value.successionCostUnits ?? 0));
  const costBps = BigInt(String(value.successionCostBps ?? 0));
  const transitionDays = Math.max(0, Math.min(7, Math.trunc(Number(value.successionTransitionDays ?? 1))));
  const requested = fixedUnits > 0n ? fixedUnits : (balance * costBps) / 10000n;
  const units = requested > 0n ? (requested < balance ? requested : balance) : 0n;
  if (units === 0n) return { units, ruleVersion: rule.rows[0].id, transitionDays };
  await tx.query(
    `SELECT transaction_id FROM earth_post_transaction($1,$2,0,'SUCCESSION_COST','HOUSE',$3,$4,$5::jsonb)`,
    [`succession-cost:${houseId}:${day}`, day, houseId, rule.rows[0].id, JSON.stringify([
      { account_id: house.account_id, delta: (-units).toString(), reason_code: 'SUCCESSION_ADMINISTRATIVE_COST' },
      { account_id: ouc.account_id, delta: units.toString(), reason_code: 'SUCCESSION_ADMINISTRATIVE_COST' },
    ])],
  );
  return { units, ruleVersion: rule.rows[0].id, transitionDays };
}

export async function clearSuccessor(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  await repository.query('DELETE FROM house_succession_plans WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)', [humanId]);
  return { ok: true, successor: null };
}

export async function registerSuccessor(repository: PostgresRepository, input: { humanId: string; successorName: string; currentLifeStatus: string }): Promise<Record<string, unknown>> {
  if (!input.successorName || input.successorName.trim().length === 0) {
    return clearSuccessor(repository, input.humanId);
  }
  return repository.transaction(async (tx) => {
    if (input.currentLifeStatus === 'estate') throw new Error('Estate inheritance requires the succession settlement slice');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query('INSERT INTO house_succession_plans (house_id, successor_name, registered_game_day, status) VALUES ((SELECT house_id FROM humans WHERE id = $1), $2, $3, \'ACTIVE\') ON CONFLICT(house_id) DO UPDATE SET successor_name = excluded.successor_name, registered_game_day = excluded.registered_game_day, status = \'ACTIVE\', updated_at = CURRENT_TIMESTAMP', [input.humanId, input.successorName, day]);
    return { ok: true, successor: (await tx.query('SELECT * FROM house_succession_plans WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)', [input.humanId])).rows[0] };
  });
}

export async function getSuccessor(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const result = await repository.query('SELECT * FROM house_succession_plans WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)', [humanId]);
  return { successor: result.rows[0] ?? null };
}

export async function getLifeStatus(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [human, succession, events] = await Promise.all([
    repository.query('SELECT id, display_name, age_years, life_status, death_game_day, standing, legacy FROM humans WHERE id = $1', [humanId]),
    repository.query('SELECT * FROM house_succession_plans WHERE house_id = (SELECT house_id FROM humans WHERE id = $1)', [humanId]),
    repository.query("SELECT * FROM game_events WHERE actor_human_id = $1 AND category = 'LIFECYCLE' ORDER BY game_day DESC, game_minute DESC NULLS LAST LIMIT 20", [humanId]),
  ]);
  return { ok: true, human: human.rows[0] ?? null, succession: succession.rows[0] ?? null, events: events.rows };
}

export type MortalityInputs = {
  age: number;
  lifeConditionScore: number;
  recentFoodShortfallDays?: number;
  recentMissedMaintenanceDays?: number;
  healthServiceCoverage?: number;
  essentialServicesIndex: number;
  environmentModifier?: number;
};

export function calculateMortalityHazard(input: MortalityInputs): number {
  const age = Number(input.age);
  if (age < 65) return 0;
  if (age >= 105) return 1.0;
  const lifeCondition = Math.max(0, Math.min(100, Number(input.lifeConditionScore)));
  const serviceIndex = Math.max(0, Math.min(1, Number(input.essentialServicesIndex)));
  const healthCoverage = Math.max(0, Math.min(1, Number(input.healthServiceCoverage ?? serviceIndex)));
  const healthModifier = 1 + (100 - lifeCondition) / 50;
  const serviceModifier = 1 + (1 - healthCoverage) * 0.75 + (1 - serviceIndex) * 0.35;
  const deprivationModifier = 1
    + Math.min(1.5, Math.max(0, Number(input.recentFoodShortfallDays ?? 0)) * 0.15
      + Math.max(0, Number(input.recentMissedMaintenanceDays ?? 0)) * 0.10);
  const environmentModifier = Math.max(0.5, Math.min(2, Number(input.environmentModifier ?? 1)));
  const baseAgeHazard = 0.015 + 0.0002 * Math.pow(1.10, age - 65);
  const hazard = baseAgeHazard * healthModifier * serviceModifier * deprivationModifier * environmentModifier;
  return Math.min(0.95, Math.max(0.005, hazard));
}

export function calculateAnnualMortalityHazard(age: number, health: number, essentialServicesIndex: number): number {
  return calculateMortalityHazard({ age, lifeConditionScore: health, essentialServicesIndex });
}

/** Stable, replayable uniform roll in [0, 1), independent of textual ID shape. */
export function stableMortalityRoll(worldSeed: string, humanId: string, gameYear: number): number {
  let hash = 2166136261;
  const input = `${worldSeed}:${humanId}:${gameYear}`;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash / 4294967296;
}

/**
 * V2 mortality path. A House always receives a new Human representative;
 * private Economy V2 balances, contracts, and buildings remain on the House.
 */
export async function processHouseMortality(tx: PostgresRepository, day: number): Promise<number> {
  const world = await tx.query<{ essential_services_index: string; world_seed: string }>("SELECT essential_services_index, world_seed FROM world_state WHERE id = 'WORLD'");
  const essentialServicesIndex = Number(world.rows[0]?.essential_services_index ?? 0.68);
  const worldSeed = world.rows[0]?.world_seed ?? 'EARTH-WORLD-V2';
  const gameYear = Math.floor((day - 1) / 365) + 1;
  const candidates = await tx.query<{
    id: string; house_id: string; display_name: string; standing: number; legacy: number; age_years: number;
    house_name: string; house_legacy: number; planned_successor_name: string | null; life_condition_score: number;
    recent_food_shortfall_days: number; recent_missed_maintenance_days: number;
    health_service_coverage: string; city_service_index: string;
  }>(`SELECT human.id, human.house_id, human.display_name, human.standing, human.legacy, human.age_years,
             house.house_name, house.dynasty_legacy AS house_legacy, plan.successor_name AS planned_successor_name,
             COALESCE(condition.score, 100) AS life_condition_score,
             COALESCE(maintenance.recent_food_shortfall_days, 0) AS recent_food_shortfall_days,
             COALESCE(maintenance.recent_missed_maintenance_days, 0) AS recent_missed_maintenance_days,
             CASE WHEN city.id IS NULL OR city.residents <= 0 THEN world.essential_services_index
                  ELSE LEAST(1, city.health_capacity::numeric / GREATEST(1, city.residents)) END AS health_service_coverage,
             CASE WHEN city.id IS NULL OR city.residents <= 0 THEN world.essential_services_index
                  ELSE LEAST(1,
                    city.housing_capacity::numeric / GREATEST(1, city.residents),
                    city.energy_capacity::numeric / GREATEST(1, city.residents),
                    city.connectivity_capacity::numeric / GREATEST(1, city.residents),
                    city.health_capacity::numeric / GREATEST(1, city.residents)) END AS city_service_index
        FROM humans human
        JOIN houses house ON house.id = human.house_id AND house.status = 'ACTIVE'
        CROSS JOIN world_state world
        LEFT JOIN human_life_conditions condition ON condition.human_id = human.id
        LEFT JOIN (
          SELECT human_id,
                 COUNT(*) FILTER (WHERE food_used < food_cost OR unpaid > 0) AS recent_food_shortfall_days,
                 COUNT(*) FILTER (WHERE status IN ('unpaid', 'partial') OR unpaid > 0) AS recent_missed_maintenance_days
            FROM personal_life_maintenance
           WHERE game_day BETWEEN $1 - 7 AND $1 - 1
           GROUP BY human_id
        ) maintenance ON maintenance.human_id = human.id
        LEFT JOIN house_affiliations affiliation ON affiliation.house_id = house.id AND affiliation.status = 'ACTIVE'
        LEFT JOIN cities city ON city.id = affiliation.city_id
        LEFT JOIN house_succession_plans plan
          ON plan.house_id = house.id AND plan.status = 'ACTIVE'
       WHERE human.life_status = 'active' AND human.age_years >= 65 AND world.id = 'WORLD'
       FOR UPDATE OF human`, [day]);
  let processed = 0;
  for (const human of candidates.rows) {
    const hazard = calculateMortalityHazard({
      age: Number(human.age_years),
      lifeConditionScore: Number(human.life_condition_score),
      recentFoodShortfallDays: Number(human.recent_food_shortfall_days),
      recentMissedMaintenanceDays: Number(human.recent_missed_maintenance_days),
      healthServiceCoverage: Number(human.health_service_coverage),
      essentialServicesIndex: Number(human.city_service_index || essentialServicesIndex),
    });
    if (stableMortalityRoll(worldSeed, human.id, gameYear) >= hazard && Number(human.age_years) < 105) continue;
    const deathCorrelation = `death:${human.id}:${day}`;
    const existingDeath = await tx.query('SELECT 1 FROM succession_events WHERE predecessor_human_id = $1 AND death_game_day = $2 LIMIT 1', [human.id, day]);
    if (existingDeath.rows[0]) continue;
    const planName = human.planned_successor_name?.trim();
    const successorName = planName || `Emergency Successor of ${human.house_name}`;
    const emergency = !planName;
    const legacyContribution = Math.max(0, Math.floor(Number(human.legacy) * 0.25));
    const nextGeneration = Number((await tx.query<{ generation: number }>(
      'SELECT COALESCE(MAX(generation), 0) + 1 AS generation FROM house_lineage_records WHERE house_id = $1', [human.house_id])).rows[0]?.generation ?? 1);
    const successionCorrelation = `succession:${human.house_id}:${nextGeneration}`;
    const existingSuccession = await tx.query<{ status: string }>('SELECT status FROM succession_events WHERE id = $1', [successionCorrelation]);
    if (existingSuccession.rows[0]?.status === 'COMPLETED') continue;
    const newHumanId = `H-${human.house_id}-${nextGeneration}`;
    const newAccountId = `human-${human.house_id.toLowerCase()}-${nextGeneration}`;

    await tx.query("INSERT INTO owner_registry (id, owner_type, source_id, status) VALUES ($1, 'human', $1, 'active')", [newHumanId]);
    await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, age_years, standing, legacy, life_status, activation_game_day, political_eligibility_game_day)
                    VALUES ($1, $2, $3, $4, 20, $5, $6, 'pending', $7, $8)`,
      [newHumanId, newAccountId, human.house_id, successorName, emergency ? -100 : 0, 0, day + 1, day + 30]);
    await tx.query(
      `INSERT INTO succession_events
        (id, house_id, predecessor_human_id, successor_human_id, death_game_day, effective_game_day,
         reason, predecessor_age, predecessor_standing, predecessor_legacy, house_legacy_before, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'PREPARED')
       ON CONFLICT (id) DO NOTHING`,
      [successionCorrelation, human.house_id, human.id, newHumanId, day, day + 1, 'NATURAL_MORTALITY', human.age_years, human.standing, human.legacy, human.house_legacy],
    );

    // End the predecessor first so the one-active-human House invariant lets
    // the new generation become the incumbent.
    // Offices are mortal authority; affiliation is copied below and remains
    // attached to the House instead of being inherited as political power.
    await tx.query(`INSERT INTO governance_vacancies (institution_id, office_code, former_human_id, vacancy_game_day)
      SELECT id, 'ADMINISTRATOR', $1, $2 FROM institutions WHERE administrator_human_id = $1
      UNION ALL
      SELECT institution_id, 'CHALLENGE_AUTHORITY:' || role_code, $1, $2
        FROM proposal_challenge_authorities
       WHERE human_id = $1 AND status = 'active'`, [human.id, day]);
    await tx.query('UPDATE institutions SET administrator_human_id = NULL WHERE administrator_human_id = $1', [human.id]);
    await tx.query("UPDATE proposal_challenge_authorities SET status = 'ENDED_BY_DEATH', revoked_effective_game_day = $2 WHERE human_id = $1 AND status = 'active'", [human.id, day + 1]);
    await tx.query("UPDATE community_members SET role = 'member' WHERE human_id = $1 AND role IN ('founder', 'admin')", [human.id]);
    await tx.query('UPDATE house_heirlooms SET equipped_by_human_id = NULL WHERE house_id = $1 AND equipped_by_human_id = $2', [human.house_id, human.id]);
    await tx.query("UPDATE humans SET mortality_state = 'DEATH_CONFIRMED', life_status = 'deceased', death_game_day = $1, account_status = 'closed' WHERE id = $2", [day, human.id]);
    await tx.query('UPDATE house_lineage_records SET is_incumbent = false, successor_human_id = $5, death_game_day = $1, cause_of_death = $2, legacy_score = $3 WHERE human_id = $4 AND house_id = $6', [day, 'Natural Biological Mortality', human.legacy, human.id, newHumanId, human.house_id]);
    const successionCost = await applyOptionalSuccessionCost(tx, human.house_id, day);
    await tx.query('UPDATE houses SET dynasty_legacy = dynasty_legacy + $1, generation = GREATEST(generation, $2), current_human_id = $3, succession_transition_until_game_day = $4 WHERE id = $5', [legacyContribution, nextGeneration, newHumanId, day + successionCost.transitionDays, human.house_id]);
    await tx.query('UPDATE succession_events SET house_legacy_after = house_legacy_before + $1, rule_version = $2 WHERE id = $3', [legacyContribution, successionCost.ruleVersion, successionCorrelation]);
    await tx.query('INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES ($1, \'active\', $2, 100, $3)', [newHumanId, day, emergency ? 'emergency-succession' : 'planned-succession']);
    await tx.query('INSERT INTO house_lineage_records (id, house_id, human_id, predecessor_human_id, successor_human_id, generation, name, title, birth_game_day, is_incumbent, legacy_score) VALUES ($1,$2,$3,$4,NULL,$5,$6,$7,$8,false,$9) ON CONFLICT (house_id, generation) DO NOTHING', [`LINEAGE-${human.house_id}-${nextGeneration}`, human.house_id, newHumanId, human.id, nextGeneration, successorName, emergency ? 'Emergency Successor' : 'House Successor', day, 0]);
    await tx.query("UPDATE humans SET mortality_state = 'DECEASED' WHERE id = $1", [human.id]);

    // Persistent affiliation belongs to the House. Refresh only the
    // compatibility membership projection for the new representative; the
    // authoritative house_affiliations row is deliberately unchanged.
    await tx.query('SELECT earth_project_house_affiliation_to_memberships($1)', [human.house_id]);
    if (planName) await tx.query("UPDATE house_succession_plans SET status = 'USED', used_game_day = $1, updated_at = CURRENT_TIMESTAMP WHERE house_id = $2 AND status = 'ACTIVE'", [day, human.house_id]);
    await createGameEvent(tx, {
      id: `HUMAN-DIED-${successionCorrelation}`,
      category: 'LIFECYCLE',
      eventType: 'HUMAN_DIED',
      gameDay: day,
      actorHouseId: human.house_id,
      actorHumanId: human.id,
      subjectType: 'HUMAN',
      subjectId: human.id,
      title: `${human.display_name} died`,
      details: { successionEventId: successionCorrelation, predecessorId: human.id, successorId: newHumanId, houseId: human.house_id, predecessorFinalLegacy: Number(human.legacy) },
      correlationId: `human-died:${successionCorrelation}`,
    });
    await createGameEvent(tx, {
      id: successionCorrelation,
      category: 'LIFECYCLE',
      eventType: 'HOUSE_SUCCESSION',
      gameDay: day,
      actorHouseId: human.house_id,
      actorHumanId: human.id,
      subjectType: 'HOUSE',
      subjectId: human.house_id,
      title: emergency ? `${successorName} inherited the House` : `${successorName} succeeded ${human.display_name}`,
      details: { successionEventId: successionCorrelation, predecessorId: human.id, successorId: newHumanId, houseId: human.house_id, emergency, houseLegacyContribution: legacyContribution, successionCostUnits: successionCost.units.toString(), successionCostRuleVersion: successionCost.ruleVersion, successionTransitionDays: successionCost.transitionDays },
      correlationId: `house-succession:${successionCorrelation}`,
    });
    await createNotification(tx, {
      id: `NOTIFICATION-${successionCorrelation}`,
      houseId: human.house_id,
      humanId: newHumanId,
      notificationType: 'life',
      title: 'Succession completed',
      body: `Your House succession is complete. ${successorName} now represents the House.`,
      entityType: 'succession',
      entityId: successionCorrelation,
      gameDay: day,
      correlationId: successionCorrelation,
    });
    await tx.query('UPDATE succession_events SET status = \'COMPLETED\', completed_at = CURRENT_TIMESTAMP WHERE id = $1 AND status = \'PREPARED\'', [successionCorrelation]);
    processed += 1;
  }
  return processed;
}

/** Activate successors at the opening of their effective game day. */
export async function activatePendingHouseSuccessors(tx: PostgresRepository, day: number): Promise<number> {
  const pending = await tx.query<{ id: string; house_id: string; predecessor_human_id: string | null }>(
    `SELECT human.id, human.house_id, lineage.predecessor_human_id
       FROM humans human
       JOIN houses house ON house.id = human.house_id AND house.status = 'ACTIVE'
       LEFT JOIN house_lineage_records lineage ON lineage.human_id = human.id
      WHERE human.life_status = 'pending' AND human.activation_game_day <= $1
      FOR UPDATE OF human`, [day]);
  for (const successor of pending.rows) {
    await tx.query("UPDATE humans SET life_status = 'active' WHERE id = $1 AND life_status = 'pending'", [successor.id]);
    await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [successor.id, successor.house_id]);
    await tx.query('UPDATE house_lineage_records SET is_incumbent = true WHERE human_id = $1', [successor.id]);
    await tx.query('UPDATE buildings SET managed_by_human_id = $1 WHERE owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $2) AND ownership_class = \'private\'', [successor.id, successor.house_id]);
    await tx.query('UPDATE community_members SET human_id = $1 WHERE house_id = $2', [successor.id, successor.house_id]);
  }
  return pending.rows.length;
}
