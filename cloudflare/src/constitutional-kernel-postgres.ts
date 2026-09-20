import type { PostgresRepository } from './repository.ts';
import { CONSTITUTIONAL_RULE_DEFINITIONS, constitutionalInputSpec, earthDefaultRuleCode, resolveConstitutionalRuleSet, type EffectiveRuleSet } from './v5-constitution.ts';
import { constitutionArticleLabel, constitutionRuleLabel, type ConstitutionArticle, type ConstitutionChangeSet, type ConstitutionProgressiveSchedule, type ConstitutionRuleView, type ConstitutionVersionHistory, type ScheduledConstitutionChange } from './constitution-read-model.ts';

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
  const versionIds: Record<string, string> = { ...earth.versionIds, ...corporation.versionIds };
  for (const definition of CONSTITUTIONAL_RULE_DEFINITIONS) {
    if (definition.authorityModel !== 'EARTH_DEFAULT_CORPORATION_OVERRIDE' || versionIds[definition.code]) continue;
    const inheritedCode = earthDefaultRuleCode(definition.code);
    if (inheritedCode && earth.versionIds[inheritedCode]) versionIds[definition.code] = earth.versionIds[inheritedCode];
  }
  return { rules, versionIds, provenance, gameDay: input.gameDay };
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
    SELECT id, rule_code, authority_type, authority_id, version, value_json,
           effective_from_game_day, effective_to_game_day, status, proposal_id
      FROM constitutional_rule_versions_v5
     WHERE (authority_type = 'EARTH' AND authority_id = 'EARTH')
        OR (authority_type = 'CORPORATION' AND authority_id = $1)
     ORDER BY rule_code, effective_from_game_day DESC, version DESC`, [input.corporationId ?? '']),
    repository.query(`
      SELECT id, rule_code, authority_type, authority_id, version, value_json,
             effective_from_game_day, proposal_id
        FROM constitutional_rule_versions_v5
       WHERE effective_from_game_day > $1
         AND status = 'ACTIVE'
         AND ((authority_type = 'EARTH' AND authority_id = 'EARTH')
           OR (authority_type = 'CORPORATION' AND authority_id = $2))
       ORDER BY effective_from_game_day, rule_code, version`, [input.gameDay, input.corporationId ?? '']),
  ]);
  const scheduleAuthorityIds = input.corporationId ? ['EARTH', input.corporationId] : ['EARTH'];
  const scheduleRows = (await repository.query(`
    SELECT s.id, s.code, s.basis_type, s.authority_institution_id, s.version,
           s.effective_from_game_day,
           b.ordinal, b.lower_bound_units::TEXT AS lower_bound_units,
           b.upper_bound_units::TEXT AS upper_bound_units,
           b.marginal_multiplier_numerator::TEXT AS marginal_multiplier_numerator,
           b.marginal_multiplier_denominator::TEXT AS marginal_multiplier_denominator
      FROM progressive_policy_schedules s
      LEFT JOIN progressive_policy_brackets b ON b.schedule_id = s.id
     WHERE s.status = 'ACTIVE'
       AND s.authority_institution_id = ANY($1::TEXT[])
     ORDER BY s.code, s.version DESC, b.ordinal`, [scheduleAuthorityIds])).rows;
  const progressiveSchedulesById = new Map<string, ConstitutionProgressiveSchedule>();
  for (const row of scheduleRows as any[]) {
    const id = String(row.id);
    const schedule = progressiveSchedulesById.get(id) ?? {
      id,
      code: String(row.code),
      basisType: String(row.basis_type),
      authorityInstitutionId: String(row.authority_institution_id),
      version: Number(row.version),
      effectiveFromGameDay: Number(row.effective_from_game_day),
      brackets: [],
    };
    if (row.ordinal != null) schedule.brackets.push({
      ordinal: Number(row.ordinal),
      lowerBoundUnits: String(row.lower_bound_units),
      upperBoundUnits: row.upper_bound_units == null ? null : String(row.upper_bound_units),
      marginalMultiplierNumerator: String(row.marginal_multiplier_numerator),
      marginalMultiplierDenominator: String(row.marginal_multiplier_denominator),
    });
    progressiveSchedulesById.set(id, schedule);
  }
  const history = historyResult.rows;
  const versionById = new Map(history.map((row: any) => [String(row.id), row]));
  const changeSetRows = (await repository.query(`
    SELECT cs.proposal_id, cs.authority_type, cs.authority_id, cs.policy_group,
           cs.changes, cs.base_version_snapshot,
           MIN(rv.effective_from_game_day) AS effective_from_game_day
      FROM constitutional_change_sets_v5 cs
      LEFT JOIN constitutional_rule_versions_v5 rv
        ON rv.proposal_id = cs.proposal_id
     WHERE (cs.authority_type = 'EARTH' AND cs.authority_id = 'EARTH')
        OR (cs.authority_type = 'CORPORATION' AND cs.authority_id = $1)
     GROUP BY cs.proposal_id, cs.authority_type, cs.authority_id,
              cs.policy_group, cs.changes, cs.base_version_snapshot
     ORDER BY MIN(rv.effective_from_game_day) DESC NULLS LAST, cs.proposal_id`, [input.corporationId ?? ''])).rows;
  const changeSets: ConstitutionChangeSet[] = (changeSetRows as any[]).map((row) => ({
    proposalId: String(row.proposal_id),
    authorityType: row.authority_type,
    authorityId: String(row.authority_id),
    policyGroup: String(row.policy_group),
    changes: Array.isArray(row.changes) ? row.changes : [],
    baseVersionSnapshot: row.base_version_snapshot && typeof row.base_version_snapshot === 'object' ? row.base_version_snapshot : {},
    effectiveFromGameDay: row.effective_from_game_day == null ? null : Number(row.effective_from_game_day),
  }));
  const ruleViews: ConstitutionRuleView[] = definitionsResult.rows.flatMap((definition: any) => {
    const code = String(definition.rule_code);
    const registryDefinition = CONSTITUTIONAL_RULE_DEFINITIONS.find((item) => item.code === code);
    const authorityModel = String(definition.authority_model ?? 'UNKNOWN');
    const earthCode = earthDefaultRuleCode(code);
    // Corporation override definitions are a Corporation-scope view. At
    // Earth scope the mapped Earth rule is the canonical row; emitting both
    // would display the same default twice under different codes.
    if (!input.corporationId && authorityModel === 'CORPORATION_LOCAL') {
      return [];
    }
    if (!input.corporationId && authorityModel === 'EARTH_DEFAULT_CORPORATION_OVERRIDE' && earthCode && resolved.rules[earthCode] !== undefined) {
      return [];
    }
    const versionId = resolved.versionIds[code] ?? null;
    const version = versionId == null ? undefined : versionById.get(String(versionId));
    const articleCode = String(definition.article_code ?? 'OTHER_POLICY');
    const earthDefaultVersionId = earthCode ? (earth?.versionIds[earthCode] ?? null) : null;
    const earthDefaultVersion = earthDefaultVersionId == null ? undefined : versionById.get(String(earthDefaultVersionId));
    const hasEarthDefault = Boolean(earthCode && earth?.rules[earthCode] !== undefined);
    const isLocalOverride = input.corporationId != null && authorityModel === 'EARTH_DEFAULT_CORPORATION_OVERRIDE' && resolved.provenance[code] === 'CORPORATION';
    const isInherited = input.corporationId != null && authorityModel === 'EARTH_DEFAULT_CORPORATION_OVERRIDE' && hasEarthDefault && !isLocalOverride;
    return [{
      code,
      articleCode,
      valueType: String(definition.value_type ?? 'POLICY'),
      authorityModel,
      policyGroup: String(definition.policy_group ?? 'UNKNOWN'),
      amendmentClass: String(definition.amendment_class ?? 'UNKNOWN'),
      calculationKey: String(definition.calculation_key ?? code),
      allowedValues: toJsonSafe(definition.allowed_values ?? null),
      validation: toJsonSafe(definition.validation_schema ?? null),
      displayName: registryDefinition?.displayName ?? constitutionRuleLabel(code),
      description: registryDefinition?.description ?? `Canonical ${String(definition.value_type ?? 'policy').replaceAll('_', ' ').toLowerCase()} rule in the ${constitutionArticleLabel(articleCode)} policy article.`,
      articleLabel: registryDefinition?.articleLabel ?? constitutionArticleLabel(articleCode),
      order: registryDefinition?.order ?? 9999,
      inputHint: registryDefinition?.inputHint ?? 'Use the canonical input format.',
      displayHint: registryDefinition?.displayHint ?? String(definition.value_type ?? 'POLICY'),
      inputSpec: constitutionalInputSpec(CONSTITUTIONAL_RULE_DEFINITIONS.find((item) => item.code === code) ?? {
        code,
        articleCode,
        valueType: String(definition.value_type ?? 'INTEGER') as any,
        authorityModel: String(definition.authority_model ?? 'EARTH_LOCKED') as any,
        policyGroup: String(definition.policy_group ?? 'UNKNOWN'),
        calculationKey: String(definition.calculation_key ?? code),
        amendmentClass: String(definition.amendment_class ?? 'POLICY') as any,
        allowedValues: Array.isArray(definition.allowed_values) ? definition.allowed_values.map(String) : [],
        displayName: constitutionRuleLabel(code),
        description: 'Canonical Constitution rule.',
        articleLabel: constitutionArticleLabel(articleCode),
        order: 9999,
        inputHint: 'Use the canonical input format.',
        displayHint: String(definition.value_type ?? 'POLICY'),
      }, definition.validation_schema),
      resolved: {
        value: toJsonSafe(resolved.rules[code] ?? null),
        source: resolved.provenance[code] ?? null,
        versionId,
        effectiveFromGameDay: version?.effective_from_game_day == null ? null : Number(version.effective_from_game_day),
      },
      earthDefault: hasEarthDefault ? {
        value: toJsonSafe(earth!.rules[earthCode!]),
        source: 'EARTH',
        versionId: earthDefaultVersionId,
        effectiveFromGameDay: earthDefaultVersion?.effective_from_game_day == null ? null : Number(earthDefaultVersion.effective_from_game_day),
      } : null,
      inheritanceStatus: input.corporationId == null
        ? 'EARTH'
        : isLocalOverride
          ? 'LOCAL_OVERRIDE'
          : isInherited
            ? 'INHERITED'
            : null,
    }];
  });
  ruleViews.sort((left, right) => left.order - right.order || left.code.localeCompare(right.code));
  const articlesByCode = new Map<string, ConstitutionArticle>();
  for (const rule of ruleViews) {
    const article = articlesByCode.get(rule.articleCode) ?? {
      articleCode: rule.articleCode,
      displayName: rule.articleLabel,
      ruleCodes: [],
    };
    article.ruleCodes.push(rule.code);
    articlesByCode.set(rule.articleCode, article);
  }
  const scheduledChanges: ScheduledConstitutionChange[] = scheduledResult.rows.map((row: any) => ({
    ruleCode: String(row.rule_code),
    authorityType: row.authority_type,
    authorityId: String(row.authority_id),
    versionId: String(row.id),
    version: Number(row.version),
    effectiveFromGameDay: Number(row.effective_from_game_day),
    proposalId: row.proposal_id == null ? null : String(row.proposal_id),
    value: toJsonSafe(row.value_json?.value ?? row.value_json?.scheduleId ?? row.value_json),
  }));
  const versionHistory: ConstitutionVersionHistory[] = history.map((row: any) => ({
    ruleCode: String(row.rule_code),
    authorityType: row.authority_type,
    authorityId: String(row.authority_id),
    versionId: String(row.id),
    version: Number(row.version),
    effectiveFromGameDay: Number(row.effective_from_game_day),
    effectiveToGameDay: row.effective_to_game_day == null ? null : Number(row.effective_to_game_day),
    status: String(row.status),
    proposalId: row.proposal_id == null ? null : String(row.proposal_id),
    value: toJsonSafe(row.value_json?.value ?? row.value_json?.scheduleId ?? row.value_json),
  }));
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
    ruleViews: toJsonSafe(ruleViews),
    articles: toJsonSafe([...articlesByCode.values()]),
    versionHistory: toJsonSafe(versionHistory),
    changeSets: toJsonSafe(changeSets),
    scheduledChangeViews: toJsonSafe(scheduledChanges),
    scheduleBrackets: toJsonSafe(scheduleBrackets),
    progressiveSchedules: toJsonSafe([...progressiveSchedulesById.values()]),
    generatedFrom: 'postgres-constitutional-kernel-v5',
  };
}
