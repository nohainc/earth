import type { PostgresRepository } from './repository.ts';
import { resolveConstitutionalRuleSet, type EffectiveRuleSet } from './v5-constitution.ts';

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
        AND v.status = 'ACTIVE' AND v.effective_from_game_day <= $3
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
): Promise<{ rules: EffectiveRuleSet; versionIds: Record<string, string>; gameDay: number }> {
  const earth = await rulesFor(repository, 'EARTH', 'EARTH', input.gameDay);
  if (!input.corporationId) return { rules: earth.values, versionIds: earth.versionIds, gameDay: input.gameDay };
  const corporation = await rulesFor(repository, 'CORPORATION', input.corporationId, input.gameDay);
  const rules = resolveConstitutionalRuleSet({ earth: earth.values, corporation: corporation.values });
  return { rules, versionIds: { ...earth.versionIds, ...corporation.versionIds }, gameDay: input.gameDay };
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
  await tx.query(
    `INSERT INTO resolved_constitution_snapshots_v5
       (id, authority_type, authority_id, game_day, rules_json, version_ids)
     VALUES ($1,$2,$3,$4,$5::JSONB,$6::JSONB)
     ON CONFLICT (authority_type, authority_id, game_day) DO UPDATE SET
       rules_json = EXCLUDED.rules_json, version_ids = EXCLUDED.version_ids`,
    [id, input.authorityType, input.authorityId, input.gameDay, JSON.stringify(resolved.rules, (_, value) => typeof value === 'bigint' ? value.toString() : value), JSON.stringify(resolved.versionIds)],
  );
  return { id, versionIds: resolved.versionIds };
}

export async function getConstitutionReadModel(
  repository: PostgresRepository,
  input: { gameDay: number; corporationId?: string },
): Promise<Record<string, unknown>> {
  const resolved = await resolveEffectiveConstitution(repository, input);
  const history = (await repository.query(`
    SELECT rule_code, authority_type, authority_id, version, value_json,
           effective_from_game_day, effective_to_game_day, status, proposal_id
      FROM constitutional_rule_versions_v5
     WHERE (authority_type = 'EARTH' AND authority_id = 'EARTH')
        OR (authority_type = 'CORPORATION' AND authority_id = $1)
     ORDER BY rule_code, effective_from_game_day DESC, version DESC`, [input.corporationId ?? ''])).rows;
  return {
    gameDay: input.gameDay,
    corporationId: input.corporationId ?? null,
    rules: toJsonSafe(resolved.rules),
    versionIds: resolved.versionIds,
    history: toJsonSafe(history),
    generatedFrom: 'postgres-constitutional-kernel-v5',
  };
}
