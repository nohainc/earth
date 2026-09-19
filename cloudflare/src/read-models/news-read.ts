import type { PostgresRepository } from '../repository.ts';
import type { NewsImportance, NewsScopeType, NewsTopic } from '../news-publications-postgres.ts';

type NewsCursor = {
  day: number;
  minute: number;
  occurredAt: string;
  id: string;
  scope?: NewsScopeType;
  topic?: NewsTopic;
  importance?: NewsImportance;
};

export type NewsFilters = {
  scope?: NewsScopeType;
  topic?: NewsTopic;
  importance?: NewsImportance;
};

export type NewsStory = {
  id: string;
  scope: { type: NewsScopeType; id?: string; name?: string };
  topic: NewsTopic;
  importance: NewsImportance;
  headline: string;
  summary: string;
  gameDay: number;
  gameMinute: number | null;
  relatedEntity: { type?: string; id?: string; name?: string };
  action: { route?: string; entityId?: string; label?: string };
  viewer: { isNew: boolean };
  publicationKey: string;
};

function encodeCursor(value: NewsCursor): string {
  return btoa(JSON.stringify(value));
}

function decodeCursor(value: string | undefined): NewsCursor | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as Partial<NewsCursor>;
    if (!Number.isInteger(parsed.day) || !Number.isInteger(parsed.minute) ||
        typeof parsed.occurredAt !== 'string' || typeof parsed.id !== 'string') return null;
    return {
      day: parsed.day,
      minute: parsed.minute,
      occurredAt: parsed.occurredAt,
      id: parsed.id,
      ...(parsed.scope == null ? {} : { scope: parsed.scope as NewsScopeType }),
      ...(parsed.topic == null ? {} : { topic: parsed.topic as NewsTopic }),
      ...(parsed.importance == null ? {} : { importance: parsed.importance as NewsImportance }),
    };
  } catch {
    return null;
  }
}

/**
 * The player-facing publication read model. Generic events and notifications
 * are not exposed directly; only explicit rows in news_publications enter it.
 */
export async function listNews(
  repository: PostgresRepository,
  houseId: string,
  limit: number,
  before?: string,
  filters: NewsFilters = {},
): Promise<Record<string, unknown>> {
  const boundedLimit = Math.max(1, Math.min(50, limit));
  const cursor = decodeCursor(before);
  if (before && !cursor) throw new Error('Invalid news cursor');
  if (cursor && (cursor.scope !== filters.scope || cursor.topic !== filters.topic || cursor.importance !== filters.importance)) {
    throw new Error('News cursor does not match the requested filters');
  }
  const result = await repository.query(`
    SELECT p.id AS news_id, p.publication_key, p.publication_key AS correlation_id,
           p.scope_type AS scope, p.scope_id, p.scope_name,
           p.topic, p.importance, p.game_day, NULLIF(p.game_minute, -1) AS game_minute, p.published_at AS occurred_at,
           p.headline, p.summary, p.related_entity_type, p.related_entity_id,
           p.related_entity_name, p.action_route AS related_route,
           p.action_entity_id, p.action_label,
           CASE WHEN r.house_id IS NULL OR
             (p.game_day, COALESCE(p.game_minute, -1), p.published_at, p.id) >
             (r.last_seen_game_day, r.last_seen_game_minute, r.last_seen_published_at, r.last_seen_publication_id)
             THEN TRUE ELSE FALSE END AS viewer_is_new
    FROM news_publications p
    LEFT JOIN house_news_read_state r ON r.house_id = $9
    WHERE ($1::BIGINT IS NULL OR (p.game_day, COALESCE(p.game_minute, -1), p.published_at, p.id) < ($1, $2, $3::TIMESTAMPTZ, $4))
      AND ($6::TEXT IS NULL OR p.scope_type = $6)
      AND ($7::TEXT IS NULL OR p.topic = $7)
      AND ($8::TEXT IS NULL OR p.importance = $8)
    ORDER BY p.game_day DESC, p.game_minute DESC NULLS LAST, p.published_at DESC, p.id DESC
    LIMIT $5`, [cursor?.day ?? null, cursor?.minute ?? null, cursor?.occurredAt ?? null, cursor?.id ?? null, boundedLimit + 1, filters.scope ?? null, filters.topic ?? null, filters.importance ?? null, houseId]);
  const rows = result.rows as Array<Record<string, unknown>>;
  const hasMore = rows.length > boundedLimit;
  const items = hasMore ? rows.slice(0, boundedLimit) : rows;
  const last = items[items.length - 1];
  const news: NewsStory[] = items.map((row) => {
    const route = row.related_route == null ? undefined : String(row.related_route);
    const relatedType = row.related_entity_type == null ? undefined : String(row.related_entity_type);
    const relatedId = row.related_entity_id == null ? undefined : String(row.related_entity_id);
    const scopeType = String(row.scope ?? 'EARTH') as NewsScopeType;
    return {
      id: String(row.news_id),
      scope: {
        type: scopeType,
        ...(row.scope_id == null ? {} : { id: String(row.scope_id) }),
        ...(row.scope_name == null ? {} : { name: String(row.scope_name) }),
      },
      topic: String(row.topic) as NewsTopic,
      importance: String(row.importance) as NewsImportance,
      headline: String(row.headline),
      summary: String(row.summary ?? ''),
      gameDay: Number(row.game_day),
      gameMinute: row.game_minute == null ? null : Number(row.game_minute),
      relatedEntity: relatedType || relatedId || row.related_entity_name ? { type: relatedType, id: relatedId, name: row.related_entity_name == null ? undefined : String(row.related_entity_name) } : {},
      action: route ? { route, entityId: row.action_entity_id == null ? undefined : String(row.action_entity_id), label: row.action_label == null ? undefined : String(row.action_label) } : {},
      viewer: { isNew: row.viewer_is_new === true },
      publicationKey: String(row.publication_key),
    };
  });
  return {
    ok: true,
    news,
    nextCursor: hasMore && last ? encodeCursor({
      day: Number(last.game_day), minute: Number(last.game_minute ?? -1),
      occurredAt: String(last.occurred_at), id: String(last.news_id),
      ...(filters.scope == null ? {} : { scope: filters.scope }),
      ...(filters.topic == null ? {} : { topic: filters.topic }),
      ...(filters.importance == null ? {} : { importance: filters.importance }),
    }) : null,
    generatedAt: new Date().toISOString(),
  };
}

export async function markNewsSeen(
  repository: PostgresRepository,
  houseId: string,
  publicationKey: string,
): Promise<void> {
  await repository.query(`
    INSERT INTO house_news_read_state (
      house_id, last_seen_game_day, last_seen_game_minute,
      last_seen_published_at, last_seen_publication_id
    )
    SELECT $1, game_day, COALESCE(game_minute, -1), published_at, id
    FROM news_publications
    WHERE publication_key = $2
    ON CONFLICT (house_id) DO UPDATE SET
      last_seen_game_day = EXCLUDED.last_seen_game_day,
      last_seen_game_minute = EXCLUDED.last_seen_game_minute,
      last_seen_published_at = EXCLUDED.last_seen_published_at,
      last_seen_publication_id = EXCLUDED.last_seen_publication_id,
      updated_at = CURRENT_TIMESTAMP
    WHERE (EXCLUDED.last_seen_game_day, EXCLUDED.last_seen_game_minute,
           EXCLUDED.last_seen_published_at, EXCLUDED.last_seen_publication_id) >
          (house_news_read_state.last_seen_game_day, house_news_read_state.last_seen_game_minute,
           house_news_read_state.last_seen_published_at, house_news_read_state.last_seen_publication_id)`,
    [houseId, publicationKey],
  );
}
