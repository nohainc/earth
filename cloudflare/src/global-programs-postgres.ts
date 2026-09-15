import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

async function currentDay(tx: PostgresRepository): Promise<number> {
  return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
}

export async function listGlobalPrograms(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const programs = await repository.query(`SELECT id, program_type, name, description, status, authorized_units::TEXT, funded_units::TEXT, spent_units::TEXT, progress_units::TEXT, target_units::TEXT, authorization_proposal_id, created_game_day, completed_game_day FROM global_programs ORDER BY status, created_game_day DESC, id`);
  return { programs: programs.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function createGlobalProgram(repository: PostgresRepository, input: { programType: 'TECHNOLOGY' | 'COMMONS' | 'EMERGENCY'; name: string; description: string; targetUnits: string; authorizedUnits: string; proposalId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM global_programs WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, programId: prior.rows[0].id, correlationId: input.correlationId };
    const proposal = (await tx.query<{ subject_type: string; subject_id: string | null; action_type: string; status: string }>('SELECT subject_type, subject_id, action_type, status FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.subject_type !== 'EARTH' || proposal.subject_id !== null || proposal.action_type !== 'PUBLIC_PROJECT' || !['VOTING', 'PASSED'].includes(proposal.status)) throw new Error('Global programs require an EARTH public-project proposal');
    const target = BigInt(input.targetUnits);
    const authorized = BigInt(input.authorizedUnits);
    if (!input.name.trim() || input.name.trim().length > 120 || target <= 0n || authorized < target) throw new Error('Invalid global program definition or authority');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const id = `EARTH-PROGRAM-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO global_programs (id, program_type, name, description, authorized_units, target_units, authorization_proposal_id, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [id, input.programType, input.name.trim(), input.description.trim(), authorized.toString(), target.toString(), input.proposalId, day, input.correlationId]);
    await createGameEvent(tx, { id: `EARTH-PROGRAM-CREATED-${id}`, category: 'GOVERNANCE', eventType: 'EARTH_GLOBAL_PROGRAM_CREATED', gameDay: day, actorHumanId: input.humanId, subjectType: 'EARTH', subjectId: 'EARTH', title: input.name.trim(), details: { programId: id, programType: input.programType, targetUnits: target.toString(), authorizedUnits: authorized.toString(), proposalId: input.proposalId }, correlationId: input.correlationId });
    return { ok: true, programId: id, status: 'PROPOSED', authorizationProposalId: input.proposalId, correlationId: input.correlationId };
  });
}

export async function fundGlobalProgram(repository: PostgresRepository, input: { programId: string; proposalId: string; sourceAccountId: string; destinationAccountId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT id FROM global_program_progress WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const proposal = (await tx.query<{ status: string; action_type: string; subject_type: string }>('SELECT status, action_type, subject_type FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.status !== 'PASSED' || proposal.action_type !== 'PUBLIC_PROJECT' || proposal.subject_type !== 'EARTH') throw new Error('Global program funding requires a passed EARTH public-project proposal');
    const program = (await tx.query<{ authorized_units: string; funded_units: string; recipient_account_id: string | null }>('SELECT authorized_units::TEXT, funded_units::TEXT, recipient_account_id::TEXT FROM global_programs WHERE id = $1 AND status IN (\'PROPOSED\',\'ACTIVE\') FOR UPDATE', [input.programId])).rows[0];
    if (!program) throw new Error('Global program not found');
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n || BigInt(program.funded_units) + amount > BigInt(program.authorized_units)) throw new Error('Global program funding authority exceeded');
    const source = (await tx.query<{ id: string; balance_units: string }>('SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE id = $1 AND owner_economic_id = \'ECON-EARTH-001\' AND account_type = \'TREASURY\' AND asset_id = 1 AND status = \'ACTIVE\' FOR UPDATE', [input.sourceAccountId])).rows[0];
    const destination = (await tx.query<{ id: string }>('SELECT id::TEXT FROM economic_accounts WHERE id = $1 AND asset_id = 1 AND status = \'ACTIVE\'', [input.destinationAccountId])).rows[0];
    if (!source || !destination || source.id === destination.id || BigInt(source.balance_units) < amount) throw new Error('Global program treasury cash is insufficient or destination is unavailable');
    const day = await currentDay(tx);
    const posted = await tx.query<{ transaction_id: string; created: boolean }>('SELECT transaction_id, created FROM earth_post_transaction($1,$2,0,\'GLOBAL_PROGRAM_FUNDING\',\'EARTH\',\'EARTH\',\'earth-programs-v1\',$3::JSONB)', [input.correlationId, day, JSON.stringify([{ account_id: source.id, asset_id: 1, delta_units: (-amount).toString() }, { account_id: destination.id, asset_id: 1, delta_units: amount.toString() }])]);
    if (!posted.rows[0]?.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    await tx.query("UPDATE global_programs SET funded_units = funded_units + $1, status = 'ACTIVE', recipient_account_id = $2 WHERE id = $3", [amount.toString(), destination.id, input.programId]);
    await createGameEvent(tx, { id: `EARTH-PROGRAM-FUNDED-${input.correlationId}`, category: 'GOVERNANCE', eventType: 'EARTH_GLOBAL_PROGRAM_FUNDED', gameDay: day, actorHumanId: input.humanId, subjectType: 'EARTH', subjectId: 'EARTH', title: 'EARTH global program funded', details: { programId: input.programId, amountUnits: amount.toString(), proposalId: input.proposalId }, correlationId: input.correlationId });
    return { ok: true, programId: input.programId, fundedUnits: (BigInt(program.funded_units) + amount).toString(), transactionId: posted.rows[0].transaction_id, correlationId: input.correlationId };
  });
}

export async function advanceGlobalPrograms(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const result = await repository.query<{ id: string; funding: string; remaining: string }>(`SELECT id, LEAST(funded_units - spent_units, target_units - progress_units)::TEXT AS funding, (target_units - progress_units)::TEXT AS remaining FROM global_programs WHERE status = 'ACTIVE' AND funded_units > spent_units AND progress_units < target_units ORDER BY id LIMIT 100`);
  let advanced = 0;
  for (const program of result.rows) {
    const progress = BigInt(program.funding) < BigInt(program.remaining) ? BigInt(program.funding) : BigInt(program.remaining);
    await repository.transaction(async (tx) => {
      const locked = (await tx.query<{ id: string; funded_units: string; spent_units: string; progress_units: string; target_units: string }>('SELECT id, funded_units::TEXT, spent_units::TEXT, progress_units::TEXT, target_units::TEXT FROM global_programs WHERE id = $1 AND status = \'ACTIVE\' FOR UPDATE', [program.id])).rows[0];
      if (!locked) return;
      const actual = BigInt(locked.funded_units) - BigInt(locked.spent_units) < BigInt(locked.target_units) - BigInt(locked.progress_units) ? BigInt(locked.funded_units) - BigInt(locked.spent_units) : BigInt(locked.target_units) - BigInt(locked.progress_units);
      if (actual <= 0n) return;
      const correlation = `earth-program:${locked.id}:${gameDay}`;
      await tx.query('INSERT INTO global_program_progress (program_id, game_day, progress_units, funding_spent_units, correlation_id) VALUES ($1,$2,$3,$3,$4) ON CONFLICT (correlation_id) DO NOTHING', [locked.id, gameDay, actual.toString(), correlation]);
      await tx.query("UPDATE global_programs SET progress_units = progress_units + $1, spent_units = spent_units + $1, status = CASE WHEN progress_units + $1 >= target_units THEN 'COMPLETED' ELSE status END, completed_game_day = CASE WHEN progress_units + $1 >= target_units THEN $2 ELSE completed_game_day END WHERE id = $3", [actual.toString(), gameDay, locked.id]);
      advanced += 1;
    });
  }
  return { ok: true, gameDay, advanced };
}
