import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

const ROLE_CODES = ['CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER', 'CORPORATION_OPERATOR'] as const;
type CorporationRoleCode = typeof ROLE_CODES[number];

const ROLE_NAMES: Record<CorporationRoleCode, string> = {
  CORPORATION_EXECUTIVE: 'Executive',
  CORPORATION_TREASURER: 'Treasurer',
  CORPORATION_OPERATOR: 'Operator',
};

async function authorizedRole(repository: PostgresRepository, corporationId: string, humanId: string): Promise<{ executive: boolean; treasurer: boolean }> {
  const result = await repository.query<{ role_code: string }>(
    `SELECT role_code
       FROM institution_governance_roles
      WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE'
        AND role_code IN ('CORPORATION_EXECUTIVE', 'CORPORATION_TREASURER')`,
    [corporationId, humanId],
  );
  return {
    executive: result.rows.some((row) => row.role_code === 'CORPORATION_EXECUTIVE'),
    treasurer: result.rows.some((row) => row.role_code === 'CORPORATION_TREASURER'),
  };
}

export async function getCorporationRoles(repository: PostgresRepository, corporationId: string, viewerHumanId: string): Promise<Record<string, unknown> | null> {
  const corporation = await repository.query<{ id: string }>(
    `SELECT c.id FROM corporations c JOIN institutions i ON i.id = c.id
      WHERE c.id = $1 AND c.status = 'ACTIVE' AND i.status = 'ACTIVE'`,
    [corporationId],
  );
  if (!corporation.rows[0]) return null;

  const [roles, members, permissions] = await Promise.all([
    repository.query(`
      SELECT r.role_code AS code,
             CASE r.role_code
               WHEN 'CORPORATION_EXECUTIVE' THEN 'Executive'
               WHEN 'CORPORATION_TREASURER' THEN 'Treasurer'
               WHEN 'CORPORATION_OPERATOR' THEN 'Operator'
               ELSE r.role_code END AS name,
             r.human_id AS holder_human_id,
             h.display_name AS holder_name,
             r.status
        FROM institution_governance_roles r
        LEFT JOIN humans h ON h.id = r.human_id
       WHERE r.institution_id = $1
         AND r.role_code = ANY($2::TEXT[])
         AND r.status IN ('ACTIVE', 'VACANT')
       ORDER BY r.role_code, r.id`, [corporationId, [...ROLE_CODES]]),
    repository.query(`
      SELECT h.id AS human_id, h.display_name
        FROM humans h
        JOIN house_affiliations ha ON ha.house_id = h.house_id
                                  AND ha.corporation_id = $1
                                  AND ha.status = 'ACTIVE'
       WHERE h.status = 'ACTIVE'
       ORDER BY h.display_name, h.id`, [corporationId]),
    authorizedRole(repository, corporationId, viewerHumanId),
  ]);

  return {
    corporationId,
    roles: roles.rows.map((row) => ({
      code: row.code,
      name: row.name,
      holderHumanId: row.holder_human_id,
      holderName: row.holder_name,
      status: row.status,
    })),
    eligibleMembers: members.rows.map((row) => ({
      humanId: row.human_id,
      displayName: row.display_name,
    })),
    viewerPermissions: {
      canAppoint: permissions.executive,
      canRemove: permissions.executive,
      canDelegateLeadership: permissions.executive,
      canProposePolicy: permissions.executive || permissions.treasurer,
    },
  };
}

export async function appointCorporationRole(repository: PostgresRepository, input: { corporationId: string; actorHumanId: string; roleCode: string; targetHumanId: string }): Promise<Record<string, unknown>> {
  if (!ROLE_CODES.includes(input.roleCode as CorporationRoleCode)) throw new Error('Unsupported Corporation role');
  return repository.transaction(async (tx) => {
    const permissions = await authorizedRole(tx, input.corporationId, input.actorHumanId);
    if (!permissions.executive) throw new Error('Corporation executive authorization is required');
    const member = await tx.query(
      `SELECT 1 FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id
        AND ha.corporation_id = $1 AND ha.status = 'ACTIVE'
       WHERE h.id = $2 AND h.status = 'ACTIVE'`,
      [input.corporationId, input.targetHumanId],
    );
    if (!member.rows[0]) throw new Error('Target human must be an active member of this Corporation');
    const clock = await readAuthoritativeGameTime(tx);
    await tx.query(
      `UPDATE institution_governance_roles SET status = 'INACTIVE'
        WHERE institution_id = $1 AND role_code = $2 AND status = 'ACTIVE'`,
      [input.corporationId, input.roleCode],
    );
    const vacant = await tx.query<{ id: string }>(
      `SELECT id FROM institution_governance_roles
        WHERE institution_id = $1 AND role_code = $2 AND status = 'VACANT'
        ORDER BY id LIMIT 1 FOR UPDATE`,
      [input.corporationId, input.roleCode],
    );
    if (vacant.rows[0]) {
      await tx.query(
        `UPDATE institution_governance_roles SET human_id = $1, status = 'ACTIVE', effective_from_game_day = $3 WHERE id = $2`,
        [input.targetHumanId, vacant.rows[0].id, clock.gameDay],
      );
    } else {
      await tx.query(
        `INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status, effective_from_game_day)
         VALUES ($1, $2, $3, 'ACTIVE', $4)`,
        [input.corporationId, input.targetHumanId, input.roleCode, clock.gameDay],
      );
    }
    return { ok: true, corporationId: input.corporationId, roleCode: input.roleCode, targetHumanId: input.targetHumanId, gameDay: clock.gameDay };
  });
}

export async function removeCorporationRole(repository: PostgresRepository, input: { corporationId: string; actorHumanId: string; roleCode: string }): Promise<Record<string, unknown>> {
  if (!ROLE_CODES.includes(input.roleCode as CorporationRoleCode)) throw new Error('Unsupported Corporation role');
  return repository.transaction(async (tx) => {
    const permissions = await authorizedRole(tx, input.corporationId, input.actorHumanId);
    if (!permissions.executive) throw new Error('Corporation executive authorization is required');
    const clock = await readAuthoritativeGameTime(tx);
    const result = await tx.query(
      `UPDATE institution_governance_roles SET status = 'VACANT', human_id = NULL
        WHERE institution_id = $1 AND role_code = $2 AND status = 'ACTIVE'
       RETURNING human_id`,
      [input.corporationId, input.roleCode],
    );
    return { ok: true, corporationId: input.corporationId, roleCode: input.roleCode, removedHumanId: result.rows[0]?.human_id ?? null, gameDay: clock.gameDay };
  });
}
