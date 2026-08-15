import type { PostgresRepository } from './repository';

async function gameDay(tx: PostgresRepository): Promise<number> {
  const result = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

async function expire(tx: PostgresRepository, day: number): Promise<void> {
  const expired = await tx.query<{ id: string; human_id: string; institution_id: string; role_id: string }>("SELECT id, human_id, institution_id, role_id FROM role_assignments WHERE status = 'active' AND ends_game_day <= $1", [day]);
  await tx.query("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
  await tx.query("UPDATE authority_delegations SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
  for (const role of expired.rows) {
    await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'expired',$5,'term_completed') ON CONFLICT DO NOTHING", [crypto.randomUUID(), role.human_id, role.institution_id, role.role_id, day]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`ROLE-EXPIRED-${role.human_id}-${role.role_id}-${day}`, role.human_id, 'governance', 'Role term completed', `Your term for role ${role.role_id} has ended.`, role.role_id]);
  }
}

async function eligible(tx: PostgresRepository, humanId: string, institutionId: string, eligibility: string): Promise<boolean> {
  if (eligibility === 'representative') return Boolean((await tx.query('SELECT m.human_id FROM memberships m JOIN corporations c ON c.id = m.corporation_id WHERE m.human_id = $1 AND (c.institution_id = $2 OR m.corporation_id = $2)', [humanId, institutionId])).rows[0]);
  if (eligibility === 'city-representative') return Boolean((await tx.query('SELECT human_id FROM memberships WHERE human_id = $1 AND city_id IS NOT NULL AND corporation_id IS NULL', [humanId])).rows[0]);
  if (eligibility === 'resident') return Boolean((await tx.query('SELECT m.human_id FROM memberships m JOIN cities c ON c.id = m.city_id WHERE m.human_id = $1 AND (c.institution_id = $2 OR m.city_id = $2)', [humanId, institutionId])).rows[0]);
  return Boolean((await tx.query('SELECT m.human_id FROM memberships m JOIN corporations c ON c.id = m.corporation_id WHERE m.human_id = $1 AND (c.institution_id = $2 OR m.corporation_id = $2)', [humanId, institutionId])).rows[0]);
}

export async function listRoles(repository: PostgresRepository): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = await gameDay(tx);
    await expire(tx, day);
    const roles = await tx.query("SELECT institution_roles.*, role_assignments.human_id, role_assignments.started_game_day, role_assignments.ends_game_day, role_assignments.status AS assignment_status, authority_delegations.delegate_id, authority_delegations.ends_game_day AS delegation_ends_game_day FROM institution_roles LEFT JOIN role_assignments ON role_assignments.role_id = institution_roles.id AND role_assignments.status = 'active' LEFT JOIN authority_delegations ON authority_delegations.role_id = institution_roles.id AND authority_delegations.status = 'active' WHERE institution_roles.status = 'active' ORDER BY institution_roles.institution_id, institution_roles.id");
    return { roles: roles.rows };
  });
}

export async function changeRole(repository: PostgresRepository, input: { humanId: string; roleId: string; action: 'claim' | 'resign' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = await tx.query<{ id: string; institution_id: string; term_days: number; eligibility: string }>("SELECT id, institution_id, term_days, eligibility FROM institution_roles WHERE id = $1 AND status = 'active' FOR UPDATE", [input.roleId]);
    if (!role.rows[0]) throw new Error('Role not found');
    const day = await gameDay(tx);
    await expire(tx, day);
    if (input.action === 'resign') {
      const assignment = await tx.query('UPDATE role_assignments SET status = \'resigned\' WHERE role_id = $1 AND human_id = $2 AND status = \'active\' RETURNING id', [input.roleId, input.humanId]);
      if (assignment.rowCount !== 1) throw new Error('Active role assignment not found');
      await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'resigned',$5,'voluntary_resignation')", [crypto.randomUUID(), input.humanId, role.rows[0].institution_id, input.roleId, day]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`ROLE-RESIGNED-${input.humanId}-${input.roleId}-${day}`, input.humanId, 'governance', 'Role resigned', `You resigned from role ${input.roleId}.`, input.roleId]);
      return { ok: true, status: 'resigned' };
    }
    const human = await tx.query<{ political_eligibility_game_day: number }>('SELECT political_eligibility_game_day FROM humans WHERE id = $1 AND life_status = \'active\'', [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    if (day < Number(human.rows[0].political_eligibility_game_day ?? 0)) throw new Error(`Political maturity is reached on game day ${human.rows[0].political_eligibility_game_day}`);
    if (!(await eligible(tx, input.humanId, role.rows[0].institution_id, role.rows[0].eligibility))) throw new Error('Human is not eligible for this role');
    if ((await tx.query("SELECT id FROM role_assignments WHERE role_id = $1 AND status = 'active' FOR UPDATE", [input.roleId])).rows[0]) throw new Error('Role is already occupied');
    const assignmentId = crypto.randomUUID();
    const ends = day + Math.min(90, Math.max(7, Number(role.rows[0].term_days)));
    await tx.query('INSERT INTO role_assignments (id,role_id,institution_id,human_id,started_game_day,ends_game_day) VALUES ($1,$2,$3,$4,$5,$6)', [assignmentId, input.roleId, role.rows[0].institution_id, input.humanId, day, ends]);
    await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'claimed',$5,'role_claim')", [crypto.randomUUID(), input.humanId, role.rows[0].institution_id, input.roleId, day]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`ROLE-CLAIMED-${input.humanId}-${input.roleId}-${day}`, input.humanId, 'governance', 'Role claimed', `You now hold role ${input.roleId} until game day ${ends}.`, input.roleId]);
    return { ok: true, assignment: (await tx.query('SELECT * FROM role_assignments WHERE id = $1', [assignmentId])).rows[0] };
  });
}

export async function changeDelegation(repository: PostgresRepository, input: { humanId: string; roleId: string; action: 'delegate' | 'recall'; delegateHumanId?: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = await tx.query<{ id: string; institution_id: string }>("SELECT id, institution_id FROM institution_roles WHERE id = $1 AND status = 'active' FOR UPDATE", [input.roleId]);
    if (!role.rows[0]) throw new Error('Role not found');
    const day = await gameDay(tx);
    await expire(tx, day);
    const assignment = await tx.query<{ id: string; human_id: string; ends_game_day: number }>("SELECT id, human_id, ends_game_day FROM role_assignments WHERE role_id = $1 AND status = 'active' FOR UPDATE", [input.roleId]);
    if (!assignment.rows[0]) throw new Error('Role is not currently occupied');
    if (input.action === 'delegate') {
      const delegateId = input.delegateHumanId?.trim() ?? '';
      if (assignment.rows[0].human_id !== input.humanId) throw new Error('Only the current role holder may delegate authority');
      if (!delegateId || delegateId === input.humanId || !(await tx.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [delegateId])).rows[0]) throw new Error('Delegate must be another active Human');
      await tx.query("UPDATE authority_delegations SET status = 'revoked' WHERE role_id = $1 AND status = 'active'", [input.roleId]);
      const delegationId = crypto.randomUUID();
      await tx.query('INSERT INTO authority_delegations (id,institution_id,role_id,delegator_id,delegate_id,starts_game_day,ends_game_day) VALUES ($1,$2,$3,$4,$5,$6,$7)', [delegationId, role.rows[0].institution_id, input.roleId, input.humanId, delegateId, day, assignment.rows[0].ends_game_day]);
      await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'delegated',$5,$6)", [crypto.randomUUID(), input.humanId, role.rows[0].institution_id, input.roleId, day, `delegated_to:${delegateId}`]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`ROLE-DELEGATED-${delegationId}`, delegateId, 'governance', 'Authority delegated', `You may exercise delegated authority for role ${input.roleId} until game day ${assignment.rows[0].ends_game_day}.`, input.roleId]);
      return { ok: true, delegation: (await tx.query('SELECT * FROM authority_delegations WHERE id = $1', [delegationId])).rows[0] };
    }
    if (!(await eligible(tx, input.humanId, role.rows[0].institution_id, 'member'))) throw new Error('Human is not eligible to recall this role');
    await tx.query("UPDATE role_assignments SET status = 'resigned' WHERE id = $1 AND status = 'active'", [assignment.rows[0].id]);
    await tx.query("UPDATE authority_delegations SET status = 'revoked' WHERE role_id = $1 AND status = 'active'", [input.roleId]);
    await tx.query("INSERT INTO authority_events (id,human_id,institution_id,role_id,action,game_day,reason) VALUES ($1,$2,$3,$4,'recalled',$5,$6)", [crypto.randomUUID(), input.humanId, role.rows[0].institution_id, input.roleId, day, `recalled_holder:${assignment.rows[0].human_id}`]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [crypto.randomUUID(), assignment.rows[0].human_id, 'governance', 'Role recalled', `Your term for role ${input.roleId} was recalled.`, input.roleId]);
    return { ok: true, status: 'recalled', roleId: input.roleId };
  });
}
