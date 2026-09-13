import type { PostgresRepository } from '../repository.ts';

export async function listEvents(repository: PostgresRepository, limit: number, category?: string): Promise<Record<string, unknown>> {
  const result = await repository.query(
    "SELECT id, category, event_type, game_day, game_minute, actor_house_id, actor_human_id, institution_id, subject_type, subject_id, title, details, correlation_id, created_at AS occurred_at FROM game_events WHERE event_type NOT IN ('world_clock', 'scheduled_tick') AND LOWER(COALESCE(title, '')) NOT LIKE '%public world announcement%' AND ($2::text IS NULL OR category = $2) ORDER BY game_day DESC, game_minute DESC NULLS LAST, created_at DESC LIMIT $1",
    [limit, category ?? null],
  );
  return { ok: true, events: result.rows, generatedAt: new Date().toISOString() };
}

export async function listHistory(repository: PostgresRepository, limit: number): Promise<Record<string, unknown>> {
  const boundedLimit = Math.max(1, Math.min(100, limit));
  const events = await repository.query(`
    SELECT id, category, event_type, game_day, game_minute, actor_house_id, actor_human_id,
           institution_id, subject_type, subject_id, title, details, correlation_id, created_at
    FROM game_events
    ORDER BY game_day DESC, game_minute DESC NULLS LAST, created_at DESC LIMIT $1
  `, [boundedLimit]).catch(() => ({ rows: [] }));
  const deceased = await repository.query(`
    SELECT h.id AS human_id, h.display_name, h.death_game_day,
           h.age_years AS final_age_years, h.standing AS final_standing,
           h.final_legacy, house.house_name, successor.display_name AS successor_name
    FROM humans h
    JOIN houses house ON house.id = h.house_id
    LEFT JOIN succession_events succession ON succession.predecessor_human_id = h.id
    LEFT JOIN humans successor ON successor.id = succession.successor_human_id
    WHERE h.status = 'DECEASED'
    ORDER BY h.death_game_day DESC NULLS LAST, h.final_legacy DESC, h.id LIMIT $1
  `, [boundedLimit]).catch(() => ({ rows: [] }));
  return { events: events.rows, rankings: [], deceased: deceased.rows };
}
