import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { WORLD_CONDITIONS_RULES_VERSION, conditionIsEffective } from './world-conditions.ts';

export async function listWorldConditions(repository: PostgresRepository, gameDay?: number) {
  const day = gameDay ?? (await readAuthoritativeGameTime(repository)).gameDay;
  const conditions = await repository.query(`SELECT id, condition_code, title, description, source_type, source_id, scope_type, scope_id, effect_type, target_key, modifier_bps, effective_from_game_day, effective_to_game_day, rules_version FROM world_conditions WHERE effective_from_game_day <= $1 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1) ORDER BY effective_from_game_day, id`, [day]);
  return {
    ok: true,
    gameDay: day,
    rulesVersion: WORLD_CONDITIONS_RULES_VERSION,
    conditions: conditions.rows.map((row) => ({
      id: row.id, code: row.condition_code, title: row.title, description: row.description,
      source: { type: row.source_type, id: row.source_id },
      scope: { type: row.scope_type, id: row.scope_id }, effect: { type: row.effect_type, target: row.target_key, modifierBps: Number(row.modifier_bps) },
      effectiveFromGameDay: Number(row.effective_from_game_day), effectiveToGameDay: row.effective_to_game_day == null ? null : Number(row.effective_to_game_day),
      effective: conditionIsEffective({ effectiveFromGameDay: Number(row.effective_from_game_day), effectiveToGameDay: row.effective_to_game_day == null ? null : Number(row.effective_to_game_day) }, day),
    })),
    generatedFrom: 'postgres-canonical-facts',
  };
}
