import type { PostgresRepository } from './repository.ts';
import type { HouseProfile } from './house-profile.ts';

async function transactional<T>(repository: PostgresRepository, work: () => Promise<T>): Promise<T> {
  return repository.transaction(async () => work());
}

export async function getHouseProfile(
  client: PostgresRepository,
  houseId: string,
  humanId: string,
): Promise<{
  ok: boolean;
  houseProfile: HouseProfile;
}> {
  return transactional(client, async () => {
    const [houseRes, humanRes, affiliationRes, successionRes, settlementRes, walletRes, rulesRes, lineageHumansRes, lineageEventsRes, historyRes] = await Promise.all([
      client.query<{
        id: string;
        current_human_id: string | null;
        house_name: string;
        motto: string | null;
        status: string;
        generation: number;
        dynasty_legacy: string;
        created_at: string;
      }>(`SELECT id, current_human_id, house_name, motto, status, generation, dynasty_legacy::TEXT, created_at
            FROM houses WHERE id = $1 LIMIT 1`, [houseId]),
      client.query<{
        id: string;
        display_name: string;
        birth_game_day: number;
        age_years: number;
        status: string;
        standing: string;
        final_legacy: string;
      }>(`SELECT id, display_name, birth_game_day, age_years, status, standing::TEXT, final_legacy::TEXT
            FROM humans WHERE id = $1 AND house_id = $2`, [humanId, houseId]),
      client.query<{ corporation_id: string; corporation_name: string; joined_game_day: number; status: string }>(
        `SELECT ha.corporation_id, i.name AS corporation_name, ha.joined_game_day, ha.status
           FROM house_affiliations ha
           JOIN institutions i ON i.id = ha.corporation_id
          WHERE ha.house_id = $1 AND ha.status = 'ACTIVE'
          ORDER BY ha.joined_game_day DESC, ha.id DESC LIMIT 1`, [houseId]),
      client.query<{ successor_name: string; registered_game_day: number; status: string }>(
        `SELECT successor_name, registered_game_day, status
           FROM house_succession_plans
          WHERE house_id = $1 AND status = 'ACTIVE' LIMIT 1`, [houseId]),
      client.query<{
        corporation_id: string | null;
        residential_capacity_units: string;
        productive_capacity_units: string;
        total_capacity_units: string;
        active_building_count: number;
        profile_version: string;
        source_game_day: number;
        dirty: boolean;
      }>(`SELECT corporation_id, residential_capacity_units::TEXT, productive_capacity_units::TEXT,
                total_capacity_units::TEXT, active_building_count, profile_version, source_game_day, dirty
           FROM v5_house_settlement_profiles WHERE house_id = $1`, [houseId]),
      client.query<{ wallet_units: string }>(
        `SELECT COALESCE(SUM(a.balance_units), 0)::TEXT AS wallet_units
           FROM economic_accounts a
           JOIN owner_registry o ON o.economic_id = a.owner_economic_id
          WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1
            AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [houseId]),
      client.query<{ rule_code: string; value: string; rule_id: string }>(
        `SELECT DISTINCT ON (rule_code)
                rule_code, value_json->>'value' AS value, id AS rule_id
           FROM constitutional_rule_versions_v5
          WHERE authority_type = 'EARTH' AND authority_id = 'EARTH'
            AND rule_code = ANY($1::TEXT[])
            AND status IN ('ACTIVE', 'RETIRED')
            AND effective_from_game_day <= (
              SELECT game_day FROM earth_get_current_game_time()
            )
            AND (effective_to_game_day IS NULL OR effective_to_game_day >= (
              SELECT game_day FROM earth_get_current_game_time()
            ))
          ORDER BY rule_code, effective_from_game_day DESC, version DESC`,
        [['EARTH.SUCCESSION.COST_UNITS', 'EARTH.SUCCESSION.COST_BPS', 'EARTH.SUCCESSION.TRANSITION_DAYS']],
      ),
      client.query<{
        id: string; display_name: string; birth_game_day: number; death_game_day: number | null;
        status: string; standing: string; final_legacy: string;
      }>(`SELECT id, display_name, birth_game_day, death_game_day, status,
                  standing::TEXT, final_legacy::TEXT
             FROM humans WHERE house_id = $1
            ORDER BY birth_game_day ASC, id ASC`, [houseId]),
      client.query<{
        id: string; predecessor_human_id: string; successor_human_id: string | null;
        death_game_day: number; effective_game_day: number; generation: number; status: string;
      }>(`SELECT id::TEXT, predecessor_human_id, successor_human_id, death_game_day,
                  effective_game_day, generation, status
             FROM succession_events WHERE house_id = $1
            ORDER BY generation ASC, id ASC`, [houseId]),
      client.query<{
        id: string; game_day: number; game_minute: number | null; category: string;
        event_type: string; title: string; subject_type: string | null; subject_id: string | null;
      }>(`SELECT id, game_day, game_minute, category, event_type, title, subject_type, subject_id
             FROM game_events
            WHERE (actor_house_id = $1
               OR (subject_type = 'HOUSE' AND subject_id = $1)
               OR actor_human_id IN (SELECT id FROM humans WHERE house_id = $1))
              AND category IN ('LIFECYCLE', 'BUILDING', 'AFFILIATION', 'INSTITUTION', 'RESEARCH')
            ORDER BY game_day DESC, game_minute DESC NULLS LAST, created_at DESC
            LIMIT 25`, [houseId]),
    ]);

    const house = houseRes.rows[0];
    const human = humanRes.rows[0];
    if (!house) throw new Error('House not found for authenticated account');
    if (!human || human.status !== 'ACTIVE') throw new Error('Human account not found or inactive');

    const affiliation = affiliationRes.rows[0];
    const succession = successionRes.rows[0];
    const settlement = settlementRes.rows[0];
    const ruleValues = new Map(rulesRes.rows.map((row) => [row.rule_code, row.value]));
    const fixedCostUnits = ruleValues.get('EARTH.SUCCESSION.COST_UNITS') ?? '0';
    const percentageCostBps = ruleValues.get('EARTH.SUCCESSION.COST_BPS') ?? '0';
    const transitionDays = Math.max(0, Math.min(7, Math.trunc(Number(ruleValues.get('EARTH.SUCCESSION.TRANSITION_DAYS') ?? 1))));
    const walletUnits = walletRes.rows[0]?.wallet_units ?? '0';
    const wallet = BigInt(walletUnits);
    const fixed = BigInt(fixedCostUnits);
    const percentage = (wallet * BigInt(percentageCostBps)) / 10000n;
    const estimated = fixed > 0n ? fixed : percentage;
    const rulesVersion = rulesRes.rows.map((row) => row.rule_id).sort().join('|') || null;
    const eventsByPredecessor = new Map<string, typeof lineageEventsRes.rows[number]>();
    const eventsBySuccessor = new Map<string, typeof lineageEventsRes.rows[number]>();
    for (const event of lineageEventsRes.rows) {
      eventsByPredecessor.set(event.predecessor_human_id, event);
      if (event.successor_human_id) eventsBySuccessor.set(event.successor_human_id, event);
    }
    const lineage = lineageHumansRes.rows.map((entry) => {
      const predecessorEvent = eventsBySuccessor.get(entry.id);
      const successorEvent = eventsByPredecessor.get(entry.id);
      const isCurrent = entry.id === house.current_human_id;
      return {
        humanId: entry.id,
        displayName: entry.display_name,
        generation: predecessorEvent ? Number(predecessorEvent.generation) : successorEvent ? Math.max(1, Number(successorEvent.generation) - 1) : (isCurrent ? Number(house.generation) : 1),
        birthGameDay: Number(entry.birth_game_day),
        deathGameDay: entry.death_game_day == null ? null : Number(entry.death_game_day),
        status: entry.status,
        standing: String(entry.standing),
        finalLegacy: String(entry.final_legacy),
        relationship: isCurrent ? 'CURRENT' : predecessorEvent ? 'SUCCESSOR' : successorEvent ? 'PREDECESSOR' : 'UNLINKED',
        relatedHumanId: predecessorEvent?.predecessor_human_id ?? successorEvent?.successor_human_id ?? null,
        successionEventId: predecessorEvent?.id ?? successorEvent?.id ?? null,
        successionStatus: predecessorEvent?.status ?? successorEvent?.status ?? null,
        effectiveGameDay: predecessorEvent?.effective_game_day == null ? (successorEvent?.effective_game_day == null ? null : Number(successorEvent.effective_game_day)) : Number(predecessorEvent.effective_game_day),
      };
    });

    return {
      ok: true,
      houseProfile: {
        profileVersion: 'V5-HOUSE-PROFILE-1',
        identity: {
          id: house.id,
          name: house.house_name,
          motto: house.motto,
          status: house.status,
          generation: Number(house.generation),
          createdAt: house.created_at,
        },
        currentHuman: {
          id: human.id,
          displayName: human.display_name,
          birthGameDay: Number(human.birth_game_day),
          ageYears: Number(human.age_years),
          status: human.status,
          standing: String(human.standing),
          finalLegacy: String(human.final_legacy),
        },
        affiliation: affiliation ? {
          corporationId: affiliation.corporation_id,
          corporationName: affiliation.corporation_name,
          joinedGameDay: Number(affiliation.joined_game_day),
          status: affiliation.status,
        } : null,
        succession: succession ? {
          successorName: succession.successor_name,
          registeredGameDay: Number(succession.registered_game_day),
          status: succession.status,
        } : null,
        successionPolicy: {
          fixedCostUnits,
          percentageCostBps,
          transitionDays,
          rulesVersion,
        },
        successionQuote: {
          houseWalletUnits: walletUnits,
          estimatedCostUnits: estimated.toString(),
          calculation: fixed > 0n ? 'FIXED' : percentage > 0n ? 'PERCENTAGE' : 'NONE',
          affordable: estimated <= wallet,
        },
        lineage,
        history: historyRes.rows.map((event) => ({
          id: event.id,
          gameDay: Number(event.game_day),
          gameMinute: event.game_minute == null ? null : Number(event.game_minute),
          category: event.category,
          eventType: event.event_type,
          title: event.title,
          subjectType: event.subject_type,
          subjectId: event.subject_id,
        })),
        settlementProfile: settlement ? {
          corporationId: settlement.corporation_id,
          residentialCapacityUnits: settlement.residential_capacity_units,
          productiveCapacityUnits: settlement.productive_capacity_units,
          totalCapacityUnits: settlement.total_capacity_units,
          activeBuildingCount: Number(settlement.active_building_count),
          profileVersion: settlement.profile_version,
          sourceGameDay: Number(settlement.source_game_day),
          dirty: settlement.dirty,
        } : null,
        economics: {
          walletUnits,
          dynastyLegacyUnits: String(house.dynasty_legacy),
        },
        generatedFrom: 'postgres-canonical-facts-v5',
      },
    };
  });
}

export async function updateHouseProfile(
  client: PostgresRepository,
  houseId: string,
  input: { motto?: string; houseName?: string },
): Promise<{ ok: boolean; motto: string; houseName: string }> {
  return transactional(client, async () => {
    const houseRes = await client.query(
      `SELECT * FROM houses WHERE id = $1 LIMIT 1`,
      [houseId]
    );
    if (houseRes.rows.length === 0) {
      throw new Error('House not found for this account.');
    }
    const house = houseRes.rows[0];

    const newMotto = input.motto?.trim() || house.motto;
    const newName = input.houseName?.trim() ? input.houseName.trim() : house.house_name;

    await client.query(
      `UPDATE houses SET motto = $1, house_name = $2 WHERE id = $3`,
      [newMotto, newName, house.id]
    );

    return {
      ok: true,
      motto: newMotto,
      houseName: newName,
    };
  });
}
