import type { PostgresRepository } from './repository.ts';

export type OrganizationAction = 'ECONOMIC_OWNER' | 'ORGANIZATION_BUDGET_SPEND' | 'ORGANIZATION_OPERATE' | 'GOVERNANCE' | 'CHARTER_AMEND' | 'RESEARCH';

/** Canonical V4 authority resolver. Membership and office authority are deliberately separate. */
export async function resolveOrganizationAuthority(repository: PostgresRepository, input: { organizationId: string; humanId: string; action: OrganizationAction; amountUnits?: bigint }): Promise<{ officeId: string; officeCode: string; authorityRules: Record<string, unknown> }> {
  const result = await repository.query<{ office_id: string; office_code: string; authority_rules: Record<string, unknown> }>(`SELECT o.id AS office_id, o.office_code, o.authority_rules FROM organization_office_grants g JOIN organization_offices o ON o.id = g.office_id JOIN humans h ON h.id = g.principal_id AND h.status = 'ACTIVE' WHERE o.organization_id = $1 AND g.principal_type = 'HUMAN' AND g.principal_id = $2 AND o.status = 'ACTIVE' AND g.status = 'ACTIVE' AND g.effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD') AND (g.effective_to_game_day IS NULL OR g.effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD')) AND (o.authority_rules->'actions') ? $3 ORDER BY o.office_code LIMIT 1`, [input.organizationId, input.humanId, input.action]);
  const authority = result.rows[0];
  if (!authority) throw new Error(`Organization authority denied for ${input.action}`);
  const max = authority.authority_rules.maxAmountUnits;
  if (input.amountUnits !== undefined && max !== undefined && input.amountUnits > BigInt(String(max))) throw new Error('Organization authority amount limit exceeded');
  return authority;
}

export async function listOrganizationAuthority(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT o.office_code, o.name, o.authority_rules, g.principal_type, g.principal_id, h.display_name AS principal_name, g.effective_from_game_day, g.effective_to_game_day, g.status
    FROM organization_offices o
    LEFT JOIN LATERAL (
      SELECT g1.* FROM organization_office_grants g1
       WHERE g1.office_id = o.id AND g1.status = 'ACTIVE'
         AND g1.effective_from_game_day <= (SELECT game_day FROM world_state WHERE id = 'WORLD')
         AND (g1.effective_to_game_day IS NULL OR g1.effective_to_game_day >= (SELECT game_day FROM world_state WHERE id = 'WORLD'))
       ORDER BY g1.effective_from_game_day DESC, g1.id DESC LIMIT 1
    ) g ON TRUE
    LEFT JOIN humans h ON h.id = g.principal_id AND g.principal_type = 'HUMAN'
   WHERE o.organization_id = $1 ORDER BY o.office_code`, [organizationId]);
  return { organizationId, offices: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export type OfficeCode = 'EXECUTIVE' | 'TREASURER' | 'GOVERNOR' | 'OPERATOR' | 'RESEARCHER';

async function currentDay(tx: PostgresRepository): Promise<number> {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

async function requireActiveOrganizationMember(tx: PostgresRepository, organizationId: string, humanId: string): Promise<{ house_id: string }> {
  const member = (await tx.query<{ house_id: string }>(`SELECT h.house_id
    FROM humans h JOIN organization_memberships m ON m.house_id = h.house_id
   WHERE h.id = $1 AND h.status = 'ACTIVE' AND m.organization_id = $2 AND m.status = 'ACTIVE'`, [humanId, organizationId])).rows[0];
  if (!member) throw new Error('Office holder must be an active Organization member');
  return member;
}

export async function appointOrganizationOffice(repository: PostgresRepository, input: { organizationId: string; officeCode: OfficeCode; actorHumanId: string; targetHumanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM organization_office_grants WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, organizationId: input.organizationId, officeCode: input.officeCode, grantId: prior.id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.actorHumanId, action: 'GOVERNANCE' });
    const day = await currentDay(tx);
    const organization = (await tx.query<{ id: string }>("SELECT id FROM organizations WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.organizationId])).rows[0];
    if (!organization) throw new Error('Organization is unavailable');
    await requireActiveOrganizationMember(tx, input.organizationId, input.targetHumanId);
    const office = (await tx.query<{ id: string; office_code: OfficeCode }>("SELECT id, office_code FROM organization_offices WHERE organization_id = $1 AND office_code = $2 AND status = 'ACTIVE' FOR UPDATE", [input.organizationId, input.officeCode])).rows[0];
    if (!office) throw new Error('Organization office is unavailable');
    await tx.query("UPDATE organization_office_grants SET status = 'REVOKED', effective_to_game_day = $2 WHERE office_id = $1 AND principal_type = 'HUMAN' AND status = 'ACTIVE' AND effective_to_game_day IS NULL", [office.id, day]);
    const grantId = `GRANT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO organization_office_grants (id, office_id, principal_type, principal_id, effective_from_game_day, appointed_by_human_id, correlation_id)
      VALUES ($1,$2,'HUMAN',$3,$4,$5,$6)`, [grantId, office.id, input.targetHumanId, day, input.actorHumanId, input.correlationId]);
    return { ok: true, organizationId: input.organizationId, officeCode: office.office_code, grantId, principalType: 'HUMAN', principalId: input.targetHumanId, effectiveFromGameDay: day, appointedByHumanId: input.actorHumanId, correlationId: input.correlationId };
  });
}

export async function resignOrganizationOffice(repository: PostgresRepository, input: { organizationId: string; officeCode: OfficeCode; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string; status: string }>('SELECT g.id, g.status FROM organization_office_grants g JOIN organization_offices o ON o.id = g.office_id WHERE g.correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, organizationId: input.organizationId, officeCode: input.officeCode, grantId: prior.id, correlationId: input.correlationId };
    const day = await currentDay(tx);
    const grant = (await tx.query<{ id: string }>(`SELECT g.id
      FROM organization_office_grants g JOIN organization_offices o ON o.id = g.office_id
     WHERE o.organization_id = $1 AND o.office_code = $2 AND g.principal_type = 'HUMAN' AND g.principal_id = $3
       AND g.status = 'ACTIVE' AND g.effective_to_game_day IS NULL FOR UPDATE`, [input.organizationId, input.officeCode, input.humanId])).rows[0];
    if (!grant) throw new Error('Active office grant not found');
    await tx.query("UPDATE organization_office_grants SET status = 'REVOKED', effective_to_game_day = $2 WHERE id = $1", [grant.id, day]);
    return { ok: true, organizationId: input.organizationId, officeCode: input.officeCode, grantId: grant.id, status: 'REVOKED', effectiveToGameDay: day, correlationId: input.correlationId };
  });
}
