import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { WORLD_CONDITIONS_RULES_VERSION, conditionIsEffective, type WorldConditionsSnapshot, type WorldConditionSnapshotCondition } from './world-conditions.ts';

export async function listWorldConditions(repository: PostgresRepository, gameDay?: number, viewerHouseId?: string) {
  const day = gameDay ?? (await readAuthoritativeGameTime(repository)).gameDay;
  const viewerCorporation = viewerHouseId
    ? (await repository.query<{ id: string; name: string }>(`SELECT c.id, i.name
          FROM house_affiliations ha
          JOIN corporations c ON c.id = ha.corporation_id
          JOIN institutions i ON i.id = c.id
         WHERE ha.house_id = $1 AND ha.status = 'ACTIVE'
         ORDER BY ha.joined_game_day DESC, c.id
         LIMIT 1`, [viewerHouseId])).rows[0] ?? null
    : null;
  const conditions = await repository.query(`SELECT wc.id, wc.condition_code, wc.title, wc.description, wc.source_type, wc.source_id,
           wc.scope_type, wc.scope_id, wc.severity, wc.definition_version, wc.effective_from_game_day,
           wc.effective_to_game_day, wc.rules_version,
           COALESCE(jsonb_agg(jsonb_build_object(
             'type', effect.effect_type,
             'target', effect.target_key,
             'modifierBps', effect.modifier_bps,
             'order', effect.effect_order
           ) ORDER BY effect.effect_order, effect.id) FILTER (WHERE effect.id IS NOT NULL), '[]'::jsonb) AS effects
      FROM world_conditions wc
      LEFT JOIN world_condition_effects effect ON effect.condition_id = wc.id
     WHERE wc.effective_from_game_day <= $1
       AND (wc.effective_to_game_day IS NULL OR wc.effective_to_game_day >= $1)
       AND wc.scope_type IN ('EARTH', 'CORPORATION')
     GROUP BY wc.id, wc.condition_code, wc.title, wc.description, wc.source_type, wc.source_id,
              wc.scope_type, wc.scope_id, wc.severity, wc.definition_version,
              wc.effective_from_game_day, wc.effective_to_game_day, wc.rules_version
     ORDER BY wc.effective_from_game_day, wc.id`, [day]);
  const mapped: WorldConditionSnapshotCondition[] = conditions.rows.map((row) => {
    const scopeType = String(row.scope_type) as WorldConditionSnapshotCondition['scope']['type'];
    const appliesToViewer = scopeType === 'EARTH' || (scopeType === 'CORPORATION' && viewerCorporation?.id === String(row.scope_id));
    return {
      id: String(row.id), code: String(row.condition_code), title: String(row.title), description: String(row.description),
      source: { type: String(row.source_type), id: String(row.source_id) },
      scope: { type: scopeType, id: row.scope_id == null ? null : String(row.scope_id) }, severity: String(row.severity),
      definitionVersion: String(row.definition_version), effects: (row.effects ?? []) as WorldConditionSnapshotCondition['effects'],
      effectiveFromGameDay: Number(row.effective_from_game_day), effectiveToGameDay: row.effective_to_game_day == null ? null : Number(row.effective_to_game_day),
      effective: conditionIsEffective({ effectiveFromGameDay: Number(row.effective_from_game_day), effectiveToGameDay: row.effective_to_game_day == null ? null : Number(row.effective_to_game_day) }, day),
      appliesToViewer,
      exposureReason: appliesToViewer ? (scopeType === 'EARTH' ? 'EARTHWIDE' : 'CORPORATION_AFFILIATION') : 'NOT_APPLICABLE',
    };
  });
  return {
    ok: true,
    status: 'AVAILABLE',
    worldState: mapped.length === 0 ? 'STABLE' : 'ACTIVE',
    authoritativeGameDay: day,
    snapshotVersion: `${WORLD_CONDITIONS_RULES_VERSION}:${day}`,
    rulesVersion: WORLD_CONDITIONS_RULES_VERSION,
    globalConditionCount: mapped.length,
    viewerApplicableConditionCount: mapped.filter((condition) => condition.appliesToViewer).length,
    conditions: mapped,
    generatedFrom: 'postgres-canonical-facts',
  } satisfies WorldConditionsSnapshot;
}
