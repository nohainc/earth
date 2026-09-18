import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { charterPreset, charterTemplateId, validateOrganizationCharter } from './organization-charter.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

const ARCHETYPES = new Set(['COMMUNITY', 'CORPORATION', 'COOPERATIVE', 'PUBLIC_BODY', 'RESEARCH', 'BANK']);
const CAPABILITIES = new Set(['ECONOMIC_OWNER', 'GOVERNANCE', 'TERRITORY_GOVERNOR', 'RESEARCH', 'BANKING', 'PUBLIC_PROJECTS']);

async function gameDay(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

async function requireHouse(tx: PostgresRepository, humanId: string): Promise<{ houseId: string; displayName: string }> {
  const row = (await tx.query<{ houseId: string; displayName: string }>(
    `SELECT house_id AS "houseId", display_name AS "displayName" FROM humans WHERE id = $1 AND status = 'ACTIVE'`, [humanId],
  )).rows[0];
  if (!row) throw new Error('Active Human not found');
  return row;
}

export async function listOrganizations(repository: PostgresRepository, houseId: string, archetype?: string): Promise<Record<string, unknown>> {
  const result = await repository.query(
    `SELECT o.id, o.name, o.archetype, o.join_policy, o.status, o.created_game_day,
       (m.house_id IS NOT NULL) AS is_member,
       (SELECT COUNT(*)::INTEGER FROM organization_memberships m2 WHERE m2.organization_id = o.id AND m2.status = 'ACTIVE') AS member_count,
       COALESCE((SELECT jsonb_agg(c.capability_code ORDER BY c.capability_code) FROM organization_capabilities c WHERE c.organization_id = o.id AND c.status = 'ACTIVE'), '[]'::jsonb) AS capabilities
      FROM organizations o LEFT JOIN organization_memberships m ON m.organization_id = o.id AND m.house_id = $1 AND m.status = 'ACTIVE'
     WHERE o.status = 'ACTIVE' AND ($2::TEXT IS NULL OR o.archetype = $2)
     ORDER BY is_member DESC, o.name`, [houseId, archetype ?? null],
  );
  return { organizations: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function createOrganization(repository: PostgresRepository, input: { humanId: string; name: string; archetype: string; joinPolicy?: string; capabilities?: string[]; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query(`SELECT id FROM organizations WHERE metadata->>'creation_correlation_id' = $1`, [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, organizationId: prior.rows[0].id, correlationId: input.correlationId };
    const founder = await requireHouse(tx, input.humanId);
    const name = input.name.trim();
    const archetype = input.archetype.toUpperCase();
    const joinPolicy = (input.joinPolicy ?? 'OPEN').toUpperCase();
    if (name.length < 3 || name.length > 80) throw new Error('Organization name must be 3–80 characters');
    if (!ARCHETYPES.has(archetype)) throw new Error('Unsupported Organization archetype');
    if (!['OPEN', 'REQUEST', 'INVITE_ONLY'].includes(joinPolicy)) throw new Error('Unsupported Organization join policy');
    const selected = [...new Set(input.capabilities ?? [])].map((value) => value.toUpperCase());
    if (selected.some((capability) => !CAPABILITIES.has(capability))) throw new Error('Unsupported Organization capability');
    const preset = charterPreset(archetype);
    const charter = validateOrganizationCharter({ ...preset, membershipModel: joinPolicy as 'OPEN' | 'REQUEST' | 'INVITE_ONLY', capabilities: selected.length ? selected : preset.capabilities });
    const day = await gameDay(tx);
    const id = `ORG-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO organizations (id, name, archetype, join_policy, founder_house_id, created_game_day, metadata) VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB)`, [id, name, archetype, joinPolicy, founder.houseId, day, JSON.stringify({ creation_correlation_id: input.correlationId })]);
    await tx.query(`INSERT INTO organization_memberships (organization_id, house_id, role_code, joined_game_day, correlation_id) VALUES ($1,$2,'FOUNDER',$3,$4)`, [id, founder.houseId, day, `${input.correlationId}:founder`]);
    await tx.query(`INSERT INTO comm_channels (id, scope, scope_id, name, description) VALUES ($1, 'organization', $2, $3, $4) ON CONFLICT (id) DO NOTHING`, [`channel-organization-${id}`, id, `${name} Commons`, `Shared channel for members of ${name}`]);
    await tx.query(`INSERT INTO organization_charter_versions (id, organization_id, version, template_id, charter, schema_version, effective_from_game_day, correlation_id, created_by_human_id) VALUES ($1,$2,1,$3,$4::JSONB,1,$5,$6,$7)`, [`CHARTER-${id}-V1`, id, charterTemplateId(archetype), JSON.stringify(charter), day, `${input.correlationId}:charter:v1`, input.humanId]);
    for (const capability of charter.capabilities) await tx.query(`INSERT INTO organization_capabilities (organization_id, capability_code, effective_from_game_day, rules_version) VALUES ($1,$2,$3,'organization-core-v1')`, [id, capability, day]);
    for (const [code, name, actions] of [['EXECUTIVE', 'Executive', ['ORGANIZATION_OPERATE']], ['TREASURER', 'Treasurer', ['ECONOMIC_OWNER', 'ORGANIZATION_BUDGET_SPEND']], ['GOVERNOR', 'Governor', ['GOVERNANCE', 'CHARTER_AMEND']]] as const) {
      const officeId = `OFFICE-${id}-${code}`;
      await tx.query(`INSERT INTO organization_offices (id, organization_id, office_code, name, authority_rules) VALUES ($1,$2,$3,$4,$5::JSONB)`, [officeId, id, code, name, JSON.stringify({ actions })]);
      await tx.query(`INSERT INTO organization_office_grants (id, office_id, principal_type, principal_id, effective_from_game_day, appointed_by_human_id, correlation_id) VALUES ($1,$2,'HUMAN',$3,$4,$3,$5)`, [`GRANT-${id}-FOUNDER-${code}`, officeId, input.humanId, day, `${input.correlationId}:office:${code}`]);
    }
    await createGameEvent(tx, { id: `ORG-CREATED-${id}`, category: 'ORGANIZATION', eventType: 'ORGANIZATION_CREATED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: id, title: `${name} was formed`, details: { archetype, founderHouseId: founder.houseId }, correlationId: input.correlationId });
    return { ok: true, organization: (await tx.query('SELECT * FROM organizations WHERE id = $1', [id])).rows[0], correlationId: input.correlationId };
  });
}

export async function joinOrganization(repository: PostgresRepository, input: { humanId: string; organizationId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const founder = await requireHouse(tx, input.humanId);
    const org = (await tx.query<{ id: string; name: string; join_policy: string }>("SELECT id, name, join_policy FROM organizations WHERE id = $1 AND status = 'ACTIVE' FOR UPDATE", [input.organizationId])).rows[0];
    if (!org) throw new Error('Organization not found');
    if ((await tx.query("SELECT 1 FROM organization_memberships WHERE organization_id = $1 AND house_id = $2 AND status = 'ACTIVE'", [org.id, founder.houseId])).rows[0]) return { ok: true, alreadyMember: true, organizationId: org.id };
    const day = await gameDay(tx);
    if (org.join_policy !== 'OPEN') {
      if (org.join_policy === 'INVITE_ONLY') throw new Error('Organization requires an invitation');
      await tx.query(`INSERT INTO organization_membership_requests (id, organization_id, house_id, requested_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (organization_id, house_id) WHERE status = 'PENDING' DO NOTHING`, [`ORGREQ-${crypto.randomUUID()}`, org.id, founder.houseId, day, input.correlationId]);
      return { ok: true, requested: true, organizationId: org.id, correlationId: input.correlationId };
    }
    await tx.query(`INSERT INTO organization_memberships (organization_id, house_id, role_code, joined_game_day, correlation_id) VALUES ($1,$2,'MEMBER',$3,$4)`, [org.id, founder.houseId, day, input.correlationId]);
    return { ok: true, joined: true, organizationId: org.id, correlationId: input.correlationId };
  });
}

export async function decideOrganizationRequest(repository: PostgresRepository, input: { humanId: string; organizationId: string; requestId: string; action: 'APPROVED' | 'REJECTED' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const actor = await requireHouse(tx, input.humanId);
    const admin = await tx.query(`SELECT 1
      FROM organization_memberships m
      JOIN organization_capabilities c ON c.organization_id = m.organization_id
        AND c.capability_code = 'GOVERNANCE' AND c.status = 'ACTIVE'
      WHERE m.organization_id = $1 AND m.house_id = $2 AND m.status = 'ACTIVE'
        AND m.role_code IN ('FOUNDER','ADMIN','GOVERNOR')`, [input.organizationId, actor.houseId]);
    if (!admin.rows[0]) throw new Error('Organization governance capability denied');
    const request = (await tx.query<{ id: string; house_id: string }>("SELECT id, house_id FROM organization_membership_requests WHERE id = $1 AND organization_id = $2 AND status = 'PENDING' FOR UPDATE", [input.requestId, input.organizationId])).rows[0];
    if (!request) throw new Error('Pending Organization request not found');
    const day = await gameDay(tx);
    await tx.query(`UPDATE organization_membership_requests SET status = $1, decided_game_day = $2, decided_by_house_id = $3 WHERE id = $4`, [input.action, day, actor.houseId, request.id]);
    if (input.action === 'APPROVED') await tx.query(`INSERT INTO organization_memberships (organization_id, house_id, role_code, joined_game_day, correlation_id) VALUES ($1,$2,'MEMBER',$3,$4) ON CONFLICT DO NOTHING`, [input.organizationId, request.house_id, day, `org-request:${request.id}:membership`]);
    return { ok: true, requestId: request.id, status: input.action };
  });
}

export async function listOrganizationMembers(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT m.organization_id, m.house_id, h.house_name, m.role_code, m.status, m.joined_game_day, m.left_game_day FROM organization_memberships m JOIN houses h ON h.id = m.house_id WHERE m.organization_id = $1 ORDER BY m.status, m.role_code, h.house_name`, [organizationId]);
  return { members: result.rows, organizationId, generatedFrom: 'postgres-canonical-facts' };
}

export async function listOrganizationRequests(repository: PostgresRepository, organizationId: string, houseId: string): Promise<Record<string, unknown>> {
  const allowed = await repository.query(`SELECT 1 FROM organization_memberships m JOIN organization_capabilities c ON c.organization_id = m.organization_id AND c.capability_code = 'GOVERNANCE' AND c.status = 'ACTIVE' WHERE m.organization_id = $1 AND m.house_id = $2 AND m.status = 'ACTIVE' AND m.role_code IN ('FOUNDER','ADMIN','GOVERNOR')`, [organizationId, houseId]);
  if (!allowed.rows[0]) throw new Error('Organization governance capability denied');
  const result = await repository.query(`SELECT r.id, r.organization_id, r.house_id, h.house_name, r.status, r.requested_game_day, r.decided_game_day FROM organization_membership_requests r JOIN houses h ON h.id = r.house_id WHERE r.organization_id = $1 ORDER BY r.status, r.requested_game_day, r.id`, [organizationId]);
  return { requests: result.rows, organizationId, generatedFrom: 'postgres-canonical-facts' };
}
