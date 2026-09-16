import type { PostgresRepository } from '../repository.ts';

type NewsCursor = { day: number; minute: number; occurredAt: string; id: string };

function encodeCursor(value: NewsCursor): string {
  return btoa(JSON.stringify(value));
}

function decodeCursor(value: string | undefined): NewsCursor | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as Partial<NewsCursor>;
    if (!Number.isInteger(parsed.day) || !Number.isInteger(parsed.minute) ||
        typeof parsed.occurredAt !== 'string' || typeof parsed.id !== 'string') return null;
    return { day: parsed.day, minute: parsed.minute, occurredAt: parsed.occurredAt, id: parsed.id };
  } catch {
    return null;
  }
}

/**
 * The player-facing publication read model. Generic events are not exposed
 * directly: only explicitly public categories enter this projection, and
 * correlated event/notification records collapse to one story.
 */
export async function listNews(
  repository: PostgresRepository,
  houseId: string,
  limit: number,
  before?: string,
): Promise<Record<string, unknown>> {
  const boundedLimit = Math.max(1, Math.min(50, limit));
  const cursor = decodeCursor(before);
  if (before && !cursor) throw new Error('Invalid news cursor');
  const result = await repository.query(`
    WITH candidates AS (
      SELECT
        'EVENT:' || e.id AS news_id, e.id AS source_id, e.correlation_id,
        e.category, e.event_type, e.game_day, COALESCE(e.game_minute, -1) AS game_minute,
        e.created_at AS occurred_at, e.title AS headline, e.details AS summary,
        CASE
          WHEN e.subject_type IN ('ORGANIZATION', 'CORPORATION', 'INSTITUTION', 'COMMUNITY') THEN 'ORGANIZATION'
          WHEN e.subject_type = 'TERRITORY' THEN 'TERRITORY'
          ELSE 'EARTH'
        END AS scope,
        CASE
          WHEN e.category IN ('RESEARCH', 'TECHNOLOGY') THEN 'TECHNOLOGY'
          WHEN e.category IN ('GOVERNANCE', 'INSTITUTION', 'AFFILIATION') THEN 'GOVERNANCE'
          WHEN e.category IN ('BUILDING', 'TERRITORY') THEN 'INFRASTRUCTURE'
          WHEN e.category IN ('ECONOMY', 'MARKET', 'BANKING', 'TAX', 'OWNERSHIP') THEN 'ECONOMY'
          WHEN e.category = 'LIFECYCLE' THEN 'LIFECYCLE'
          ELSE 'SOCIETY'
        END AS topic,
        CASE WHEN e.category IN ('GOVERNANCE', 'TERRITORY', 'RESEARCH', 'TECHNOLOGY') THEN 'NOTABLE' ELSE 'ROUTINE' END AS importance,
        e.subject_type AS related_entity_type, e.subject_id AS related_entity_id,
        CASE WHEN e.subject_type = 'TERRITORY' THEN 'territories'
             WHEN e.subject_type IN ('ORGANIZATION', 'CORPORATION', 'INSTITUTION', 'COMMUNITY') THEN 'corporations'
             WHEN e.category IN ('RESEARCH', 'TECHNOLOGY') THEN 'technology'
             WHEN e.category IN ('GOVERNANCE', 'ECONOMY', 'MARKET', 'BANKING', 'TAX') THEN 'constitution'
             ELSE NULL END AS related_route,
        'event' AS source_kind, 1 AS source_priority, NULL::TIMESTAMPTZ AS read_at
      FROM game_events e
      WHERE e.category IN ('GOVERNANCE', 'ORGANIZATION', 'INSTITUTION', 'TERRITORY', 'BUILDING', 'RESEARCH', 'TECHNOLOGY', 'LIFECYCLE', 'BANKING', 'TAX', 'ECONOMY')
        AND e.event_type NOT IN ('world_clock', 'scheduled_tick')
        AND NULLIF(TRIM(COALESCE(e.title, '')), '') IS NOT NULL
      UNION ALL
      SELECT
        'NOTIFICATION:' || n.id AS news_id, n.id AS source_id, n.correlation_id,
        NULL AS category, n.notification_type AS event_type, n.game_day, COALESCE(n.game_minute, -1),
        n.created_at, n.title, n.body,
        CASE WHEN LOWER(COALESCE(n.entity_type, '')) IN ('territory', 'city') THEN 'TERRITORY' ELSE 'ORGANIZATION' END,
        CASE WHEN LOWER(COALESCE(n.notification_type, '')) LIKE '%research%' OR LOWER(COALESCE(n.notification_type, '')) LIKE '%technology%' THEN 'TECHNOLOGY'
             WHEN LOWER(COALESCE(n.notification_type, '')) LIKE '%territory%' OR LOWER(COALESCE(n.entity_type, '')) IN ('territory', 'city') THEN 'INFRASTRUCTURE'
             ELSE 'SOCIETY' END,
        'NOTABLE', n.entity_type, n.entity_id,
        CASE WHEN LOWER(COALESCE(n.entity_type, '')) IN ('territory', 'city') THEN 'territories' ELSE 'corporations' END,
        'notification', 2, n.read_at
      FROM notifications n
      WHERE n.house_id = $1
        AND LOWER(COALESCE(n.entity_type, '')) IN ('territory', 'city', 'organization', 'corporation', 'institution', 'community')
    ), deduplicated AS (
      SELECT *, ROW_NUMBER() OVER (
        PARTITION BY COALESCE(NULLIF(correlation_id, ''), news_id)
        ORDER BY source_priority, occurred_at DESC, news_id
      ) AS duplicate_rank
      FROM candidates
    )
    SELECT news_id, source_id, correlation_id, scope, topic, importance,
           game_day, NULLIF(game_minute, -1) AS game_minute, occurred_at,
           headline, summary, related_entity_type, related_entity_id, related_route,
           (source_kind = 'notification' AND read_at IS NULL) AS is_new
    FROM deduplicated
    WHERE duplicate_rank = 1
      AND ($2::BIGINT IS NULL OR (game_day, game_minute, occurred_at, news_id) < ($2, $3, $4::TIMESTAMPTZ, $5))
    ORDER BY game_day DESC, game_minute DESC, occurred_at DESC, news_id DESC
    LIMIT $6`, [houseId, cursor?.day ?? null, cursor?.minute ?? null, cursor?.occurredAt ?? null, cursor?.id ?? null, boundedLimit + 1]);
  const rows = result.rows as Array<Record<string, unknown>>;
  const hasMore = rows.length > boundedLimit;
  const items = hasMore ? rows.slice(0, boundedLimit) : rows;
  const last = items[items.length - 1];
  return {
    ok: true,
    news: items,
    nextCursor: hasMore && last ? encodeCursor({
      day: Number(last.game_day), minute: Number(last.game_minute ?? -1),
      occurredAt: String(last.occurred_at), id: String(last.news_id),
    }) : null,
    generatedAt: new Date().toISOString(),
  };
}
