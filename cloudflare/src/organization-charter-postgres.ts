import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { charterTemplateId, validateOrganizationCharter, type OrganizationCharter } from './organization-charter.ts';

async function currentDay(tx: PostgresRepository): Promise<number> {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

export async function listCharterTemplates(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT id, name, archetype, schema_version, charter FROM charter_templates WHERE status = 'ACTIVE' ORDER BY name`);
  return { templates: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function getOrganizationCharter(repository: PostgresRepository, organizationId: string, history = false): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT v.id, v.organization_id, v.version, v.template_id, v.charter, v.schema_version, v.effective_from_game_day, v.effective_to_game_day, v.status, v.created_at FROM organization_charter_versions v WHERE v.organization_id = $1 ${history ? '' : "AND v.effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))"} ORDER BY v.version DESC`, [organizationId]);
  if (!history && !result.rows[0]) throw new Error('Organization charter not found');
  return { organizationId, charter: history ? undefined : result.rows[0], history: history ? result.rows : undefined, generatedFrom: 'postgres-canonical-facts' };
}

async function authorizeAmendment(tx: PostgresRepository, organizationId: string, houseId: string): Promise<void> {
  const result = await tx.query(`SELECT 1 FROM organization_memberships m JOIN organization_charter_versions v ON v.organization_id = m.organization_id AND v.effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (v.effective_to_game_day IS NULL OR v.effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD')) WHERE m.organization_id = $1 AND m.house_id = $2 AND m.status = 'ACTIVE' AND m.role_code IN ('FOUNDER','ADMIN','GOVERNOR') AND (v.charter->'capabilities') ? 'GOVERNANCE'`, [organizationId, houseId]);
  if (!result.rows[0]) throw new Error('Organization governance capability denied');
}

export async function amendOrganizationCharter(repository: PostgresRepository, input: { organizationId: string; houseId: string; humanId: string; charter: unknown; correlationId: string }): Promise<Record<string, unknown>> {
  // V5 Corporations are governed by typed Constitution rule versions. Keep
  // this symbol available for historical tooling, but fail closed if any
  // caller attempts to use the old direct mutation path.
  throw new Error('Direct Charter mutation is retired; submit a V5 Constitution amendment proposal.');
  /* istanbul ignore next -- retained below only for historical migration callers. */
  const charter = validateOrganizationCharter(input.charter);
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string; version: number }>('SELECT id, version FROM organization_charter_versions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, organizationId: input.organizationId, version: prior.rows[0].version, correlationId: input.correlationId };
    await authorizeAmendment(tx, input.organizationId, input.houseId);
    const current = (await tx.query<{ version: number; charter: OrganizationCharter }>("SELECT version, charter FROM organization_charter_versions WHERE organization_id = $1 AND effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (effective_to_game_day IS NULL OR effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD')) ORDER BY version DESC FOR UPDATE", [input.organizationId])).rows[0];
    if (!current) throw new Error('Organization charter not found');
    if (JSON.stringify(current.charter) === JSON.stringify(charter)) return { ok: true, unchanged: true, organizationId: input.organizationId, version: current.version };
    const day = await currentDay(tx);
    const version = Number(current.version) + 1;
    await tx.query("UPDATE organization_charter_versions SET status = 'SUPERSEDED', effective_to_game_day = $2 WHERE organization_id = $1 AND status = 'ACTIVE' AND effective_to_game_day IS NULL", [input.organizationId, day]);
    await tx.query(`INSERT INTO organization_charter_versions (id, organization_id, version, template_id, charter, schema_version, effective_from_game_day, status, correlation_id, created_by_human_id) VALUES ($1,$2,$3,NULL,$4::JSONB,1,$5,'ACTIVE',$6,$7)`, [`CHARTER-${input.organizationId}-V${version}`, input.organizationId, version, JSON.stringify(charter), day + 1, input.correlationId, input.humanId]);
    await createGameEvent(tx, { id: `ORG-CHARTER-${input.organizationId}-V${version}`, category: 'ORGANIZATION', eventType: 'ORGANIZATION_CHARTER_AMENDED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Organization charter amended', details: { version, effectiveFromGameDay: day + 1, charter }, correlationId: input.correlationId });
    return { ok: true, organizationId: input.organizationId, version, effectiveFromGameDay: day + 1, correlationId: input.correlationId };
  });
}

export { charterTemplateId };
