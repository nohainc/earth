import type { PostgresRepository } from './repository.ts';

export type NewsScopeType = 'EARTH' | 'CORPORATION' | 'COMMUNITY';
export type NewsTopic = 'GOVERNANCE' | 'TECHNOLOGY' | 'ECONOMY' | 'INFRASTRUCTURE' | 'SOCIETY' | 'LIFECYCLE';
export type NewsImportance = 'MAJOR' | 'NOTABLE' | 'ROUTINE';
export type NewsPublicationType =
  | 'CORPORATION_FOUNDED'
  | 'TECHNOLOGY_COMPLETED'
  | 'PROPOSAL_PASSED'
  | 'MARKET_DISRUPTION'
  | 'WORLD_CONDITION'
  | 'COMMUNITY_FOUNDED'
  | 'HOUSE_MILESTONE'
  | 'LIFECYCLE_EVENT';

type NewsAction = {
  route: string;
  entityId?: string;
  label: string;
};

const NEWS_ACTIONS: Record<NewsPublicationType, { route: string; label: string; requiresEntityId?: boolean }> = {
  CORPORATION_FOUNDED: { route: 'corporations', label: 'VIEW CORPORATIONS', requiresEntityId: true },
  TECHNOLOGY_COMPLETED: { route: 'technology', label: 'VIEW TECHNOLOGY' },
  PROPOSAL_PASSED: { route: 'governance', label: 'VIEW GOVERNANCE', requiresEntityId: true },
  MARKET_DISRUPTION: { route: 'market', label: 'VIEW MARKET' },
  WORLD_CONDITION: { route: 'conditions', label: 'VIEW CONDITIONS' },
  COMMUNITY_FOUNDED: { route: 'communities', label: 'VIEW COMMUNITIES', requiresEntityId: true },
  HOUSE_MILESTONE: { route: 'house', label: 'VIEW HOUSE', requiresEntityId: true },
  LIFECYCLE_EVENT: { route: 'life', label: 'VIEW CITIZEN', requiresEntityId: true },
};

export function newsActionFor(
  publicationType: NewsPublicationType,
  entityId?: string | null,
): NewsAction {
  const definition = NEWS_ACTIONS[publicationType];
  if (!definition) throw new Error(`Unsupported News publication type: ${publicationType}`);
  if (definition.requiresEntityId && !entityId) {
    throw new Error(`${publicationType} requires an entity id`);
  }
  return {
    route: definition.route,
    ...(entityId == null ? {} : { entityId }),
    label: definition.label,
  };
}

export type NewsPublicationInput = {
  id: string;
  publicationKey: string;
  publicationType: NewsPublicationType;
  scopeType: NewsScopeType;
  scopeId?: string | null;
  scopeName?: string | null;
  topic: NewsTopic;
  importance: NewsImportance;
  headline: string;
  summary: string;
  gameDay: number;
  gameMinute?: number | null;
  relatedEntityType?: string | null;
  relatedEntityId?: string | null;
  relatedEntityName?: string | null;
  actionEntityId?: string | null;
};

/**
 * Explicit publication boundary: only callers that deliberately invoke this
 * function place a story in the public News read model.
 */
export async function publishNewsStory(
  repository: PostgresRepository,
  input: NewsPublicationInput,
): Promise<{ id: string; publicationKey: string; alreadyPublished: boolean }> {
  const action = newsActionFor(input.publicationType, input.actionEntityId);
  const result = await repository.query<{ id: string; publication_key: string; inserted: boolean }>(`
    INSERT INTO news_publications (
      id, publication_key, scope_type, scope_id, scope_name, topic, importance,
      headline, summary, game_day, game_minute,
      related_entity_type, related_entity_id, related_entity_name,
      action_route, action_entity_id, action_label
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
    ON CONFLICT (publication_key) DO NOTHING
    RETURNING id, publication_key, TRUE AS inserted`, [
    input.id,
    input.publicationKey,
    input.scopeType,
    input.scopeId ?? null,
    input.scopeName ?? null,
    input.topic,
    input.importance,
    input.headline,
    input.summary,
    input.gameDay,
    input.gameMinute ?? null,
    input.relatedEntityType ?? null,
    input.relatedEntityId ?? null,
    input.relatedEntityName ?? null,
    action.route,
    action.entityId ?? null,
    action.label,
  ]);
  if (result.rows[0]) return { id: result.rows[0].id, publicationKey: result.rows[0].publication_key, alreadyPublished: false };
  const existing = await repository.query<{ id: string; publication_key: string }>(
    'SELECT id, publication_key FROM news_publications WHERE publication_key = $1',
    [input.publicationKey],
  );
  if (!existing.rows[0]) throw new Error('News publication was not created');
  return { id: existing.rows[0].id, publicationKey: existing.rows[0].publication_key, alreadyPublished: true };
}
