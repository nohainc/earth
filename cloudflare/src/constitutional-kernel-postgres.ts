import type { PostgresRepository } from './repository.ts';
import { CONSTITUTIONAL_RULE_DEFINITIONS, resolveConstitutionalRuleSet, type EffectiveRuleSet } from './v5-constitution.ts';

type RuleRow = {
  id: string;
  rule_code: string;
  authority_type: 'EARTH' | 'CORPORATION';
  authority_id: string;
  value_json: Record<string, unknown>;
  version: number;
};

/** Keep Constitution responses JSON-safe when typed CREDIT values are BigInt. */
function toJsonSafe<T>(value: T): T {
  if (typeof value === 'bigint') return value.toString() as T;
  if (Array.isArray(value)) return value.map((item) => toJsonSafe(item)) as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, toJsonSafe(item)]),
    ) as T;
  }
  return value;
}

async function rulesFor(
  repository: PostgresRepository,
  authorityType: 'EARTH' | 'CORPORATION',
  authorityId: string,
  gameDay: number,
): Promise<{ values: EffectiveRuleSet; versionIds: Record<string, string> }> {
  const result = await repository.query<RuleRow>(
    `SELECT v.id, v.rule_code, v.authority_type, v.authority_id, v.value_json, v.version
       FROM constitutional_rule_versions_v5 v
      WHERE v.authority_type = $1 AND v.authority_id = $2
        AND v.status IN ('ACTIVE', 'RETIRED') AND v.effective_from_game_day <= $3
        AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= $3)
      ORDER BY v.rule_code, v.effective_from_game_day DESC, v.version DESC`,
    [authorityType, authorityId, gameDay],
  );
  const values: EffectiveRuleSet = {};
  const versionIds: Record<string, string> = {};
  for (const row of result.rows) {
    if (values[row.rule_code] !== undefined) continue;
    const raw = row.value_json?.value ?? row.value_json?.scheduleId ?? row.value_json;
    values[row.rule_code] = typeof raw === 'string' && /^-?\d+$/.test(raw) ? BigInt(raw) : raw as EffectiveRuleSet[string];
    versionIds[row.rule_code] = row.id;
  }
  return { values, versionIds };
}

/**
 * @mutation-boundary read-only
 * Resolves Earth plus optional Corporation overrides for one game day.
 */
export async function resolveEffectiveConstitution(
  repository: PostgresRepository,
  input: { corporationId?: string; gameDay: number },
): Promise<{ rules: EffectiveRuleSet; versionIds: Record<string, string>; provenance: Record<string, 'EARTH' | 'CORPORATION'>; gameDay: number }> {
  const earth = await rulesFor(repository, 'EARTH', 'EARTH', input.gameDay);
  if (!input.corporationId) {
    return {
      rules: earth.values,
      versionIds: earth.versionIds,
      provenance: Object.fromEntries(Object.keys(earth.values).map((code) => [code, 'EARTH'])) as Record<string, 'EARTH'>,
      gameDay: input.gameDay,
    };
  }
  const corporation = await rulesFor(repository, 'CORPORATION', input.corporationId, input.gameDay);
  const rules = resolveConstitutionalRuleSet({ earth: earth.values, corporation: corporation.values });
  const provenance: Record<string, 'EARTH' | 'CORPORATION'> = {};
  for (const definition of CONSTITUTIONAL_RULE_DEFINITIONS) {
    if (rules[definition.code] === undefined) continue;
    if (definition.authorityModel === 'EARTH_LOCKED') provenance[definition.code] = 'EARTH';
    else if (corporation.values[definition.code] !== undefined) provenance[definition.code] = 'CORPORATION';
    else provenance[definition.code] = 'EARTH';
  }
  return { rules, versionIds: { ...earth.versionIds, ...corporation.versionIds }, provenance, gameDay: input.gameDay };
}

/**
 * @mutation-boundary caller-owned-transaction deterministic-settlement
 * Materializes the resolved rule set once per authority and game day for settlement reuse.
 */
export async function materializeResolvedConstitutionSnapshot(
  tx: PostgresRepository,
  input: { authorityType: 'EARTH' | 'CORPORATION'; authorityId: string; gameDay: number },
): Promise<{ id: string; versionIds: Record<string, string> }> {
  const resolved = await resolveEffectiveConstitution(tx, {
    corporationId: input.authorityType === 'CORPORATION' ? input.authorityId : undefined,
    gameDay: input.gameDay,
  });
  const id = `CONST-${input.authorityType}-${input.authorityId}-D${input.gameDay}`;
  const inserted = await tx.query<{ id: string; version_ids: Record<string, string> }>(
    `INSERT INTO resolved_constitution_snapshots_v5
       (id, authority_type, authority_id, game_day, rules_json, version_ids, provenance_json)
     VALUES ($1,$2,$3,$4,$5::JSONB,$6::JSONB,$7::JSONB)
     ON CONFLICT (authority_type, authority_id, game_day) DO NOTHING
     RETURNING id, version_ids`,
    [id, input.authorityType, input.authorityId, input.gameDay, JSON.stringify(resolved.rules, (_, value) => typeof value === 'bigint' ? value.toString() : value), JSON.stringify(resolved.versionIds), JSON.stringify(resolved.provenance)],
  );
  if (inserted.rows[0]) return { id: inserted.rows[0].id, versionIds: inserted.rows[0].version_ids };
  const existing = (await tx.query<{ id: string; version_ids: Record<string, string> }>(
    `SELECT id, version_ids
       FROM resolved_constitution_snapshots_v5
      WHERE authority_type = $1 AND authority_id = $2 AND game_day = $3`,
    [input.authorityType, input.authorityId, input.gameDay],
  )).rows[0];
  if (!existing) throw new Error('Constitution snapshot disappeared after conflict');
  return { id: existing.id, versionIds: existing.version_ids };
}

/**
 * Read the immutable day snapshot used by settlement. The resolver fallback is
 * intentionally limited to days that have not been materialized yet (for
 * example, a read immediately before the first settlement tick).
 */
export async function getResolvedConstitutionForDay(
  repository: PostgresRepository,
  input: { corporationId?: string; gameDay: number },
): Promise<{ rules: EffectiveRuleSet; versionIds: Record<string, string>; provenance: Record<string, 'EARTH' | 'CORPORATION'>; snapshotId: string | null; gameDay: number }> {
  const authorityType = input.corporationId ? 'CORPORATION' : 'EARTH';
  const authorityId = input.corporationId ?? 'EARTH';
  const snapshot = (await repository.query<{
    id: string;
    rules_json: EffectiveRuleSet;
    version_ids: Record<string, string>;
    provenance_json: Record<string, 'EARTH' | 'CORPORATION'>;
  }>(
    `SELECT id, rules_json, version_ids, provenance_json
       FROM resolved_constitution_snapshots_v5
      WHERE authority_type = $1 AND authority_id = $2 AND game_day = $3`,
    [authorityType, authorityId, input.gameDay],
  )).rows[0];
  if (snapshot) {
    return {
      rules: snapshot.rules_json,
      versionIds: snapshot.version_ids,
      provenance: snapshot.provenance_json,
      snapshotId: snapshot.id,
      gameDay: input.gameDay,
    };
  }
  const resolved = await resolveEffectiveConstitution(repository, input);
  return { ...resolved, snapshotId: null };
}

export async function getConstitutionReadModel(
  repository: PostgresRepository,
  input: { gameDay: number; corporationId?: string },
): Promise<Record<string, unknown>> {
  const resolved = await getResolvedConstitutionForDay(repository, input);
  const earth = input.corporationId
    ? await getResolvedConstitutionForDay(repository, { gameDay: input.gameDay })
    : undefined;
  const [definitionsResult, historyResult, scheduledResult] = await Promise.all([
    repository.query(`
      SELECT rule_code, article_code, value_type, authority_model, policy_group,
             amendment_class, calculation_key, allowed_values, validation_schema, active
        FROM constitutional_rule_definitions_v5
       WHERE active = TRUE
       ORDER BY article_code, rule_code`),
    repository.query(`
    SELECT rule_code, authority_type, authority_id, version, value_json,
           effective_from_game_day, effective_to_game_day, status, proposal_id
      FROM constitutional_rule_versions_v5
     WHERE (authority_type = 'EARTH' AND authority_id = 'EARTH')
        OR (authority_type = 'CORPORATION' AND authority_id = $1)
     ORDER BY rule_code, effective_from_game_day DESC, version DESC`, [input.corporationId ?? '']),
    repository.query(`
      SELECT rule_code, authority_type, authority_id, version, value_json,
             effective_from_game_day, proposal_id
        FROM constitutional_rule_versions_v5
       WHERE effective_from_game_day > $1
         AND status = 'ACTIVE'
         AND ((authority_type = 'EARTH' AND authority_id = 'EARTH')
           OR (authority_type = 'CORPORATION' AND authority_id = $2))
       ORDER BY effective_from_game_day, rule_code, version`, [input.gameDay, input.corporationId ?? '']),
  ]);
  const history = historyResult.rows;
  const progressiveCodes = new Set(definitionsResult.rows
    .filter((definition) => definition.value_type === 'PROGRESSIVE_SCHEDULE_REF')
    .map((definition) => String(definition.rule_code)));
  const scheduleIds = [...new Set(Object.entries(resolved.rules).flatMap(([code, value]) => {
    if (progressiveCodes.has(code) && typeof value === 'string' && value.trim()) return [value];
    if (value && typeof value === 'object' && !Array.isArray(value) && 'scheduleId' in value) return [String((value as Record<string, unknown>).scheduleId)];
    return [];
  }))];
  const scheduleBrackets = scheduleIds.length === 0 ? {} : Object.fromEntries((await repository.query(`
      SELECT schedule_id, ordinal, lower_bound_units, upper_bound_units,
             marginal_multiplier_numerator, marginal_multiplier_denominator
        FROM progressive_policy_brackets
       WHERE schedule_id = ANY($1::TEXT[])
       ORDER BY schedule_id, ordinal`, [scheduleIds])).rows.reduce((groups, row) => {
    const schedule = String(row.schedule_id);
    const entries = groups.get(schedule) ?? [];
    entries.push(row);
    groups.set(schedule, entries);
    return groups;
  }, new Map<string, Record<string, unknown>[]>()));
  return {
    gameDay: input.gameDay,
    corporationId: input.corporationId ?? null,
    rules: toJsonSafe(resolved.rules),
    versionIds: resolved.versionIds,
    provenance: resolved.provenance,
    snapshotId: resolved.snapshotId,
    earthRules: earth ? toJsonSafe(earth.rules) : null,
    earthVersionIds: earth?.versionIds ?? null,
    earthSnapshotId: earth?.snapshotId ?? null,
    definitions: toJsonSafe(definitionsResult.rows),
    history: toJsonSafe(history),
    scheduledChanges: toJsonSafe(scheduledResult.rows),
    scheduleBrackets: toJsonSafe(scheduleBrackets),
    generatedFrom: 'postgres-constitutional-kernel-v5',
  };
}
