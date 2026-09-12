import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';

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
    repository.query('SELECT * FROM life_events WHERE human_id = $1 ORDER BY game_day DESC LIMIT 20', [humanId]),
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
  const lifeCondition = Math.max(0, Math.min(100, Number(input.lifeConditionScore ?? 100)));
  const serviceIndex = Math.max(0, Math.min(1, Number(input.essentialServicesIndex ?? 0.68)));
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
    const eventId = deathCorrelation;
    if ((await tx.query("SELECT 1 FROM life_events WHERE id IN ($1, $2) AND event_type = 'death'", [eventId, `DEATH-${human.id}-${day}`])).rows[0]) continue;

    const membership = await tx.query<{ corporation_id: string | null; city_id: string | null; joined_game_day: number }>(
      'SELECT corporation_id, city_id, joined_game_day FROM house_affiliations WHERE house_id = $1 AND status = \'ACTIVE\' FOR UPDATE', [human.house_id]);
    const historicalLineage = await tx.query<{ title: string }>(
      'SELECT title FROM house_lineage_records WHERE human_id = $1 ORDER BY generation DESC LIMIT 1', [human.id]);
    const majorTitles = historicalLineage.rows.map(({ title }) => title).filter(Boolean);
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
    await tx.query(`INSERT INTO deceased_profiles
      (human_id, display_name, death_game_day, final_age_years, final_standing, final_legacy,
       successor_name, corporation_id, city_id, major_titles, achievements, cause_of_death)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb,$11::jsonb,$12)
      ON CONFLICT (human_id) DO UPDATE SET
        successor_name = EXCLUDED.successor_name,
        death_game_day = EXCLUDED.death_game_day`,
      [human.id, human.display_name, day, human.age_years, human.standing, human.legacy, successorName,
        membership.rows[0]?.corporation_id ?? null, membership.rows[0]?.city_id ?? null,
        JSON.stringify(majorTitles), JSON.stringify([]), 'Natural Biological Mortality']);
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
    await tx.query('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES ($1,$2,\'death\',$3,$4,0)', [eventId, human.id, day, successorName]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,\'human.succession\',$3,$4) ON CONFLICT (id) DO NOTHING', [successionCorrelation, day, emergency ? `${successorName} inherited the House` : `${successorName} succeeded ${human.display_name}`, toNanoMarkup({ successionEventId: successionCorrelation, predecessorId: human.id, successorId: newHumanId, houseId: human.house_id, emergency, predecessorFinalLegacy: Number(human.legacy), houseLegacyContribution: legacyContribution, successionCostUnits: successionCost.units.toString(), successionCostRuleVersion: successionCost.ruleVersion, successionTransitionDays: successionCost.transitionDays })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'life\',\'Succession completed\',$3,$4) ON CONFLICT DO NOTHING', [`NOTIFICATION-${successionCorrelation}`, newHumanId, `Your House succession is complete. ${successorName} now represents the House.`, successionCorrelation]);
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

export async function processMortality(tx: PostgresRepository, day: number): Promise<number> {
  const service = await tx.query<{ essential_services_index: string }>("SELECT essential_services_index FROM world_state WHERE id = 'WORLD'");
  const essentialServicesIndex = Number(service.rows[0]?.essential_services_index ?? 0.68);
  // The joined succession/account rows are nullable. Lock only the human rows;
  // locking the whole outer-join result makes PostgreSQL reject the query.
  const humans = await tx.query<{ id: string; account_id: string | null; display_name: string; standing: number; legacy: number; age_years: number; successor_name: string | null; successor_human_id: string | null; estate_period_days: number | null; balance: string; life_condition_score: number }>('SELECT humans.id, account_balances.account_id, humans.display_name, humans.standing, humans.legacy, humans.age_years, succession_plans.successor_name, succession_plans.successor_human_id, succession_plans.estate_period_days, COALESCE(account_balances.balance, 0) AS balance, COALESCE((SELECT score FROM human_life_conditions WHERE human_id = humans.id), 100) AS life_condition_score FROM humans LEFT JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = \'CREDIT\' WHERE humans.life_status = \'active\' AND humans.age_years >= 65 FOR UPDATE OF humans');
  let processed = 0;
  for (const human of humans.rows) {
    const age = Number(human.age_years);
    const hazard = calculateMortalityHazard({ age, lifeConditionScore: Number(human.life_condition_score), essentialServicesIndex });
    const roll = stableMortalityRoll('EARTH-WORLD-V2', human.id, Math.floor((day - 1) / 365) + 1);
    if (roll >= hazard && age < 105) continue;

    const eventId = `DEATH-${human.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM life_events WHERE id = $1 AND event_type = 'death'", [eventId])).rows[0]) continue;
    const successor = human.successor_human_id ? await tx.query<{ id: string; account_id: string }>("SELECT humans.id, account_balances.account_id FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.id = $1 AND humans.life_status = 'active' FOR UPDATE", [human.successor_human_id]) : { rows: [] } as { rows: Array<{ id: string; account_id: string }> };
    const successorRow = successor.rows[0];
    const membership = await tx.query<{ corporation_id: string | null; city_id: string | null }>('SELECT corporation_id, city_id FROM memberships WHERE human_id = $1 FOR UPDATE', [human.id]);
    const membershipRow = membership.rows[0];
    const assets = successorRow ? await tx.query<{ id: string; type: string }>("SELECT id, 'BUILDING' AS type FROM buildings WHERE owner_id = $1", [human.id]) : { rows: [] } as { rows: Array<{ id: string; type: string }> };
    const resources = successorRow ? await tx.query<{ resource: string; amount: string }>('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 FOR UPDATE', [human.id]) : { rows: [] } as { rows: Array<{ resource: string; amount: string }> };
    const grossCents = moneyToCents(human.balance);
    const inheritedCents = successorRow ? grossCents : 0n;
    const gross = Number(centsToMoney(grossCents));
    const inherited = Number(centsToMoney(inheritedCents));

    if (successorRow) {
      if (!human.account_id) throw new Error('Deceased Human Credit account is required for inheritance');
      if (inheritedCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: human.account_id, creditAccount: successorRow.account_id, amount: centsToMoney(inheritedCents), reasonType: 'inheritance', reasonId: eventId, ruleVersion: 'life-v4', correlationId: eventId });
      await tx.query('UPDATE humans SET standing = 0, legacy = 0 WHERE id = $1', [successorRow.id]);
      await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [human.id, eventId, 'ownership_transfer_out', day, 0]);
      await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [successorRow.id, eventId, 'ownership_transfer_in', day, 0]);
      for (const resource of resources.rows) await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [successorRow.id, resource.resource, resource.amount]);
      await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [human.id]);
      for (const asset of assets.rows) await tx.query('INSERT INTO ownership_events (id,asset_type,asset_id,from_owner_id,to_owner_id,quantity,reason_type,reason_id,game_day) VALUES ($1,$2,$3,$4,$5,1,\'inheritance\',$6,$7)', [crypto.randomUUID(), asset.type, asset.id, human.id, successorRow.id, eventId, day]);
      await tx.query('INSERT INTO life_events (id,human_id,event_type,game_day,successor_name,estate_credits) VALUES ($1,$2,\'inheritance\',$3,$4,$5)', [`INHERIT-${human.id}-${day}`, human.id, day, human.successor_name, inherited]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'life\',\'Inheritance received\',$3,$4)', [crypto.randomUUID(), successorRow.id, `You received ${inherited} Credits and the productive assets of ${human.display_name}.`, eventId]);
    }
    if (membershipRow?.corporation_id) {
      await tx.query('UPDATE corporations SET member_count = GREATEST(0, member_count - 1) WHERE id = $1', [membershipRow.corporation_id]);
      await tx.query('INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,\'CORPORATION\',$3,\'released\',$4,\'mortality\')', [crypto.randomUUID(), human.id, membershipRow.corporation_id, day]);
    }
    if (membershipRow?.city_id) {
      await tx.query('UPDATE cities SET residents = GREATEST(0, residents - 1) WHERE id = $1', [membershipRow.city_id]);
      await tx.query('INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,\'CITY\',$3,\'released\',$4,\'mortality\')', [crypto.randomUUID(), human.id, membershipRow.city_id, day]);
    }
    await tx.query('UPDATE memberships SET city_id = NULL, corporation_id = NULL WHERE human_id = $1', [human.id]);
    await tx.query("UPDATE humans SET life_status = $1, death_game_day = $2 WHERE id = $3", [successorRow ? 'deceased' : 'estate', day, human.id]);
    // Keep the modern house tree accurate during the estate window, before
    // the next generation is selected.
    await tx.query("UPDATE house_lineage_records SET is_incumbent = false, death_game_day = $1, cause_of_death = 'Natural Biological Mortality', epitaph = 'Inscribed into the Planetary Pantheon of Earth.', lifetime_wealth = GREATEST(lifetime_wealth, $2) WHERE human_id = $3", [day, gross, human.id]);
    await tx.query('INSERT INTO life_events (id,human_id,event_type,game_day,successor_name,estate_credits) VALUES ($1,$2,\'death\',$3,$4,$5)', [eventId, human.id, day, human.successor_name, successorRow ? gross : gross]);
    if (successorRow) {
      await tx.query('INSERT INTO deceased_profiles (human_id,display_name,death_game_day,final_standing,final_legacy,successor_name,cause_of_death,epitaph) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (human_id) DO UPDATE SET successor_name = EXCLUDED.successor_name, death_game_day = EXCLUDED.death_game_day', [human.id, human.display_name, day, human.standing, human.legacy, human.successor_name, 'Natural Biological Mortality', 'Inscribed into the Planetary Pantheon of Earth.']);
      await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'human.life_event\',\'A Human entered the archive\',$3) ON CONFLICT (id) DO NOTHING', [`DEATH-${human.id}-${day}`, day, toNanoMarkup({ humanId: human.id, successor: human.successor_name, successionLevy: 0 })]);
    } else {
      await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'human.life_event\',\'A Human entered an Estate Period\',$3) ON CONFLICT (id) DO NOTHING', [`ESTATE-${human.id}-${day}`, day, toNanoMarkup({ humanId: human.id, estatePeriodDays: human.estate_period_days ?? 30 })]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'life\',\'Estate Period started\',$3,$2)', [crypto.randomUUID(), human.id, `Your estate remains available for ${human.estate_period_days ?? 30} game days before liquidation.`]);
    }
    processed += 1;
  }
  return processed;
}

export async function liquidateExpiredEstates(repository: PostgresRepository, day: number): Promise<number> {
  const estates = await repository.query<{ id: string; account_id: string | null; display_name: string; standing: number; legacy: number; balance: string }>("SELECT humans.id, account_balances.account_id, humans.display_name, humans.standing, humans.legacy, COALESCE(account_balances.balance, 0) AS balance FROM humans JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'estate' AND humans.death_game_day + succession_plans.estate_period_days <= $1", [day]);
  let processed = 0;
  for (const estate of estates.rows) {
    await repository.transaction(async (tx) => {
      const balanceCents = moneyToCents(estate.balance);
      const balance = Number(centsToMoney(balanceCents));
      if (balanceCents > 0n) {
        if (!estate.account_id) throw new Error('Estate Credit account is required for liquidation');
        await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: estate.account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(balanceCents), reasonType: 'estate_liquidation', reasonId: estate.id, ruleVersion: 'life-v3', correlationId: `ESTATE-LIQUIDATION-${estate.id}-${day}` });
      }
      await tx.query("UPDATE buildings SET status = 'closed' WHERE owner_id = $1 AND ownership_class = 'private'", [estate.id]);
      await tx.query('SELECT earth_economic_state_changed($1, $2, $3, $4, $5)', [estate.id, `ESTATE-LIQUIDATION-${estate.id}-${day}`, 'estate_liquidation', day, 0]);
      await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [estate.id]);
      await tx.query("UPDATE humans SET life_status = 'deceased' WHERE id = $1", [estate.id]);
      await tx.query('INSERT INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, NULL FROM humans WHERE id = $1 ON CONFLICT (human_id) DO NOTHING', [estate.id]);
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [`ESTATE-LIQUIDATION-${estate.id}-${day}`, day, 'human.estate_liquidated', 'An unclaimed estate was liquidated', toNanoMarkup({ humanId: estate.id, credits: balance })]);
    });
    processed += 1;
  }
  return processed;
}
