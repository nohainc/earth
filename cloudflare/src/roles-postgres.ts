import type { PostgresRepository } from './repository.ts';

export async function listRolesPostgres(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const roles = await repository.query(`SELECT r.id, r.institution_id, r.human_id, r.role_code, r.status FROM institution_governance_roles r JOIN institutions i ON i.id = r.institution_id WHERE r.status = 'ACTIVE' AND i.kind IN ('EARTH', 'CORPORATION') ORDER BY r.institution_id, r.role_code, r.id`);
  return { ok: true, roles: roles.rows };
}

export async function changeRolePostgres(repository: PostgresRepository, input: { humanId: string; roleId: string; action: 'claim' | 'resign' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = (await tx.query('SELECT id, institution_id, human_id, role_code, status FROM institution_governance_roles WHERE id = $1 FOR UPDATE', [input.roleId])).rows[0];
    if (!role) throw new Error('Role not found');
    if (input.action === 'claim') {
      if (role.status === 'ACTIVE' && role.human_id !== input.humanId) throw new Error('Role is occupied');
      await tx.query("UPDATE institution_governance_roles SET human_id = $1, status = 'ACTIVE' WHERE id = $2", [input.humanId, input.roleId]);
    } else {
      if (role.human_id !== input.humanId) throw new Error('Only the role holder may resign');
      await tx.query("UPDATE institution_governance_roles SET status = 'VACANT' WHERE id = $1", [input.roleId]);
    }
    return { ok: true, roleId: input.roleId, action: input.action };
  });
}

export async function changeDelegationPostgres(): Promise<Record<string, unknown>> {
  throw new Error('Role delegation is not enabled in baseline V1');
}
