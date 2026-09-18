import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

const TARGET_RULES = {
  version: 'catch-up-targets-v2',
  earlyDeadlineDays: 30,
  matureWorldDeadlineDays: 45,
  matureWorldDay: 3650,
  sustainableDays: 7,
} as const;

const MILESTONES = [
  { code: 'FIRST_PRODUCTIVE_ASSET', title: 'First productive asset', description: 'Operate one active or under-construction building.' },
  { code: 'FIRST_MARKET_ACTIVITY', title: 'First market activity', description: 'Keep one market order open or partially filled.' },
  { code: 'FIRST_ORGANIZATION_RELATIONSHIP', title: 'First organization relationship', description: 'Join one active organization.' },
  { code: 'FIRST_TERRITORY_OPPORTUNITY', title: 'First territory opportunity', description: 'Identify an active territory with available House capacity.' },
  { code: 'SUSTAINABLE_RESOURCE_BALANCE', title: 'Sustainable resource balance', description: 'Complete seven recent days without a recorded resource shortage.' },
] as const;

type TargetRow = {
  entry_game_day: string;
  target_game_day: string;
  target_buildings: number;
  target_open_orders: number;
  target_affiliations: number;
  target_territory_opportunities: number;
  target_sustainable_days: number;
  achieved_game_day: string | null;
  status: string;
  buildings: string;
  open_orders: string;
  affiliations: string;
  territory_opportunities: string;
  sustainable_days: string;
};

function ratio(current: number, target: number) {
  return Math.min(1, Math.max(0, current / Math.max(1, target)));
}

export async function getHouseCatchUpTargets(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const clock = await readAuthoritativeGameTime(tx);
    const day = clock.gameDay;
    const house = (await tx.query<{ created_game_day: string }>('SELECT created_game_day::TEXT FROM houses WHERE id = $1', [houseId])).rows[0];
    if (!house) return { ok: true, targets: null, generatedFrom: 'postgres-canonical-facts' };

    const support = (await tx.query<{ entry_game_day: string | null }>('SELECT entry_game_day::TEXT FROM house_entry_support WHERE house_id = $1', [houseId])).rows[0];
    const entryDay = Math.max(1, Number(support?.entry_game_day ?? house.created_game_day ?? day));
    const deadlineDays = day >= TARGET_RULES.matureWorldDay ? TARGET_RULES.matureWorldDeadlineDays : TARGET_RULES.earlyDeadlineDays;
    await tx.query(`
      INSERT INTO house_catch_up_targets
        (house_id, rules_version, entry_game_day, target_game_day, target_buildings, target_open_orders,
         target_affiliations, target_territory_opportunities, target_sustainable_days, status)
      VALUES ($1, $2, $3::BIGINT, $3::BIGINT + $4::BIGINT, 1, 1, 1, 1, $5, 'ACTIVE')
      ON CONFLICT (house_id) DO UPDATE SET
        rules_version = EXCLUDED.rules_version,
        entry_game_day = CASE WHEN house_catch_up_targets.rules_version <> $2 THEN EXCLUDED.entry_game_day ELSE house_catch_up_targets.entry_game_day END,
        target_game_day = CASE WHEN house_catch_up_targets.rules_version <> $2 THEN EXCLUDED.target_game_day ELSE house_catch_up_targets.target_game_day END,
        target_territory_opportunities = GREATEST(house_catch_up_targets.target_territory_opportunities, 1),
        target_sustainable_days = GREATEST(house_catch_up_targets.target_sustainable_days, $5),
        updated_at = CURRENT_TIMESTAMP`,
      [houseId, TARGET_RULES.version, entryDay, deadlineDays, TARGET_RULES.sustainableDays],
    );

    const row = (await tx.query<TargetRow>(`
      SELECT t.entry_game_day::TEXT, t.target_game_day::TEXT, t.target_buildings, t.target_open_orders,
             t.target_affiliations, t.target_territory_opportunities, t.target_sustainable_days,
             t.achieved_game_day::TEXT, t.status,
             (SELECT COUNT(*)::TEXT FROM buildings b WHERE b.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION')) AS buildings,
             (SELECT COUNT(*)::TEXT FROM market_orders o WHERE o.owner_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND o.status IN ('OPEN','PARTIAL')) AS open_orders,
             (SELECT COUNT(*)::TEXT FROM organization_memberships m WHERE m.house_id = $1 AND m.status = 'ACTIVE') AS affiliations,
             (SELECT COUNT(*)::TEXT FROM territories t2 LEFT JOIN territory_capacity_state s ON s.territory_id = t2.id WHERE t2.status = 'ACTIVE' AND COALESCE(s.house_capacity, 0) > COALESCE(s.active_house_count, 0)) AS territory_opportunities,
             (SELECT COUNT(*)::TEXT FROM (SELECT f.game_day FROM house_resource_daily_flow f WHERE f.house_economic_id = (SELECT economic_id FROM owner_registry WHERE id = $1) AND f.game_day BETWEEN $2 - 30 AND $2 GROUP BY f.game_day HAVING SUM(f.shortage_units) = 0) sustainable) AS sustainable_days
        FROM house_catch_up_targets t WHERE t.house_id = $1 FOR UPDATE`, [houseId, day])).rows[0];
    if (!row) return { ok: true, targets: null, generatedFrom: 'postgres-canonical-facts' };

    const current = { buildings: Number(row.buildings), openOrders: Number(row.open_orders), affiliations: Number(row.affiliations), territoryOpportunities: Number(row.territory_opportunities), sustainableDays: Number(row.sustainable_days) };
    const targets = { buildings: Number(row.target_buildings), openOrders: Number(row.target_open_orders), affiliations: Number(row.target_affiliations), territoryOpportunities: Number(row.target_territory_opportunities), sustainableDays: Number(row.target_sustainable_days) };
    const keyFor = (code: string) => code === 'FIRST_PRODUCTIVE_ASSET' ? 'buildings' : code === 'FIRST_MARKET_ACTIVITY' ? 'openOrders' : code === 'FIRST_ORGANIZATION_RELATIONSHIP' ? 'affiliations' : code === 'FIRST_TERRITORY_OPPORTUNITY' ? 'territoryOpportunities' : 'sustainableDays';
    const milestones = MILESTONES.map((milestone) => { const key = keyFor(milestone.code) as keyof typeof current; const value = current[key]; const target = targets[key]; return { ...milestone, current: value, target, progress: ratio(value, target), achieved: value >= target }; });
    const complete = milestones.every((milestone) => milestone.achieved);
    for (const milestone of milestones.filter((item) => item.achieved)) {
      await tx.query(`INSERT INTO house_catch_up_target_events (house_id, milestone_code, achieved_game_day, value_units) VALUES ($1, $2, $3, $4) ON CONFLICT (house_id, milestone_code) DO NOTHING`, [houseId, milestone.code, day, milestone.current]);
    }
    if (complete && row.achieved_game_day == null) {
      await tx.query("UPDATE house_catch_up_targets SET achieved_game_day = $2, status = 'COMPLETED', updated_at = CURRENT_TIMESTAMP WHERE house_id = $1", [houseId, day]);
      await tx.query(`UPDATE house_onboarding_progress SET completed_milestones = (SELECT jsonb_agg(DISTINCT value) FROM jsonb_array_elements(COALESCE(completed_milestones, '[]'::jsonb) || $2::jsonb) value), updated_at = CURRENT_TIMESTAMP WHERE house_id = $1`, [houseId, JSON.stringify(milestones.map((item) => item.code))]);
    }
    const events = await tx.query<{ milestone_code: string; achieved_game_day: string; value_units: string }>('SELECT milestone_code, achieved_game_day::TEXT, value_units::TEXT FROM house_catch_up_target_events WHERE house_id = $1 ORDER BY achieved_game_day, id', [houseId]);
    return { ok: true, targets: { rulesVersion: TARGET_RULES.version, entryGameDay: Number(row.entry_game_day), targetGameDay: Number(row.target_game_day), status: complete ? 'COMPLETED' : row.status, achievedGameDay: complete ? day : (row.achieved_game_day == null ? null : Number(row.achieved_game_day)), current, targets, progress: Object.fromEntries(milestones.map((item) => [item.code, item.progress])), complete, milestones, history: events.rows }, generatedFrom: 'postgres-canonical-facts' };
  });
}
