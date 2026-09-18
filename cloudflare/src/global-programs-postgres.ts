import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { runEconomicMutation } from './settlement-barrier-postgres.ts';
import { postEconomicTransaction, postSettlementTransaction } from './economic-transaction-postgres.ts';

async function currentDay(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

export async function listGlobalPrograms(repository: PostgresRepository): Promise<Record<string, unknown>> {
  const programs = await repository.query(`SELECT p.id, p.program_type, p.name, p.description, p.status, p.authorized_units::TEXT, p.funded_units::TEXT, p.spent_units::TEXT, p.progress_units::TEXT, p.target_units::TEXT, p.matching_authorized_units::TEXT, p.matching_used_units::TEXT, p.funding_deadline_game_day, p.authorization_proposal_id, p.created_game_day, p.completed_game_day, COUNT(c.id) FILTER (WHERE c.status IN ('ESCROWED','APPLIED'))::INTEGER AS supporter_count FROM global_programs p LEFT JOIN global_program_contributions c ON c.program_id = p.id GROUP BY p.id ORDER BY p.status, p.created_game_day DESC, p.id`);
  return {
    programs: programs.rows.map((program) => ({
      ...program,
      capabilities: {
        canContribute: ['PROPOSED', 'ACTIVE'].includes(String(program.status).toUpperCase()),
        canCreate: false,
      },
    })),
    generatedFrom: 'postgres-canonical-facts',
  };
}

export async function listGlobalProgramContributions(repository: PostgresRepository, programId: string, houseId: string): Promise<Record<string, unknown>> {
  const rows = await repository.query(`SELECT id, program_id, amount_units::TEXT, matching_units::TEXT, status, game_day, refunded_game_day, transaction_id::TEXT FROM global_program_contributions WHERE program_id = $1 AND house_id = $2 ORDER BY game_day DESC, id`, [programId, houseId]);
  return { programId, contributions: rows.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function createGlobalProgram(repository: PostgresRepository, input: { programType: 'TECHNOLOGY' | 'COMMONS' | 'EMERGENCY'; name: string; description: string; targetUnits: string; authorizedUnits: string; matchingAuthorizedUnits?: string; fundingDeadlineGameDay?: number; proposalId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM global_programs WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, programId: prior.rows[0].id, correlationId: input.correlationId };
    const proposal = (await tx.query<{ subject_type: string; subject_id: string | null; action_type: string; status: string }>('SELECT subject_type, subject_id, action_type, status FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.subject_type !== 'EARTH' || proposal.subject_id !== null || proposal.action_type !== 'PUBLIC_PROJECT' || !['VOTING', 'PASSED'].includes(proposal.status)) throw new Error('Global programs require an EARTH public-project proposal');
    const target = BigInt(input.targetUnits);
    const authorized = BigInt(input.authorizedUnits);
    const matching = BigInt(input.matchingAuthorizedUnits ?? '0');
    if (!input.name.trim() || input.name.trim().length > 120 || target <= 0n || authorized < target || matching < 0n || matching > authorized) throw new Error('Invalid global program definition or authority');
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const id = `EARTH-PROGRAM-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const deadline = input.fundingDeadlineGameDay ?? day + 365;
    if (!Number.isInteger(deadline) || deadline < day) throw new Error('Funding deadline must be a future game day');
    await tx.query(`INSERT INTO global_programs (id, program_type, name, description, authorized_units, matching_authorized_units, target_units, funding_deadline_game_day, authorization_proposal_id, created_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, [id, input.programType, input.name.trim(), input.description.trim(), authorized.toString(), matching.toString(), target.toString(), deadline, input.proposalId, day, input.correlationId]);
    await createGameEvent(tx, { id: `EARTH-PROGRAM-CREATED-${id}`, category: 'GOVERNANCE', eventType: 'EARTH_GLOBAL_PROGRAM_CREATED', gameDay: day, actorHumanId: input.humanId, subjectType: 'EARTH', subjectId: 'EARTH', title: input.name.trim(), details: { programId: id, programType: input.programType, targetUnits: target.toString(), authorizedUnits: authorized.toString(), proposalId: input.proposalId }, correlationId: input.correlationId });
    return { ok: true, programId: id, status: 'PROPOSED', fundingDeadlineGameDay: deadline, authorizationProposalId: input.proposalId, correlationId: input.correlationId };
  });
}

export async function fundGlobalProgram(repository: PostgresRepository, input: { programId: string; proposalId: string; sourceAccountId: string; destinationAccountId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
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
    const day = clock.gameDay;
    const posted = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'GLOBAL_PROGRAM_FUNDING',
      sourceType: 'EARTH',
      sourceId: 'EARTH',
      rulesVersion: 'earth-programs-v1',
      entries: [
        { accountId: source.id, assetId: 1, deltaUnits: (-amount).toString() },
        { accountId: destination.id, assetId: 1, deltaUnits: amount.toString() },
      ],
    }, clock);
    if (!posted.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    await tx.query("UPDATE global_programs SET funded_units = funded_units + $1, status = 'ACTIVE', recipient_account_id = $2 WHERE id = $3", [amount.toString(), destination.id, input.programId]);
    await createGameEvent(tx, { id: `EARTH-PROGRAM-FUNDED-${input.correlationId}`, category: 'GOVERNANCE', eventType: 'EARTH_GLOBAL_PROGRAM_FUNDED', gameDay: day, actorHumanId: input.humanId, subjectType: 'EARTH', subjectId: 'EARTH', title: 'EARTH global program funded', details: { programId: input.programId, amountUnits: amount.toString(), proposalId: input.proposalId }, correlationId: input.correlationId });
    return { ok: true, programId: input.programId, fundedUnits: (BigInt(program.funded_units) + amount).toString(), transactionId: posted.transactionId, correlationId: input.correlationId };
  });
}

export async function contributeToGlobalProgram(repository: PostgresRepository, input: { programId: string; houseId: string; sourceAccountId: string; amountUnits: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return runEconomicMutation(repository, async (tx, clock) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM global_program_contributions WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contributionId: prior.rows[0].id, correlationId: input.correlationId };
    const program = (await tx.query<{ authorized_units: string; funded_units: string; matching_authorized_units: string; matching_used_units: string; status: string; funding_deadline_game_day: number }>('SELECT authorized_units::TEXT, funded_units::TEXT, matching_authorized_units::TEXT, matching_used_units::TEXT, status, funding_deadline_game_day FROM global_programs WHERE id = $1 FOR UPDATE', [input.programId])).rows[0];
    if (!program || !['PROPOSED', 'ACTIVE'].includes(program.status)) throw new Error('Global program is not accepting contributions');
    const amount = BigInt(input.amountUnits);
    if (amount <= 0n) throw new Error('Contribution must be positive');
    const day = clock.gameDay;
    if (day > Number(program.funding_deadline_game_day)) throw new Error('Global program funding deadline has passed');
    const source = (await tx.query<{ id: string; balance_units: string }>(`SELECT a.id::TEXT, a.balance_units::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.id = $2 AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE' FOR UPDATE`, [input.houseId, input.sourceAccountId])).rows[0];
    const earth = (await tx.query<{ id: string; balance_units: string }>(`SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = 'ECON-EARTH-001' AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE' FOR UPDATE`)).rows[0];
    const sink = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.owner_type = 'SYSTEM' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' ORDER BY a.id LIMIT 1`)).rows[0];
    if (!source || !earth || !sink || BigInt(source.balance_units) < amount) throw new Error('House wallet balance is insufficient or program escrow is unavailable');
    const remainingAuthority = BigInt(program.authorized_units) - BigInt(program.funded_units);
    if (amount > remainingAuthority) throw new Error('Contribution exceeds remaining program authority');
    const daily = await tx.query<{ total: string }>(`SELECT COALESCE(SUM(amount_units), 0)::TEXT AS total FROM global_program_contributions WHERE program_id = $1 AND house_id = $2 AND game_day = $3 AND status = 'ESCROWED'`, [input.programId, input.houseId, day]);
    if (BigInt(daily.rows[0]?.total ?? '0') + amount > 10000n) throw new Error('House daily program contribution limit exceeded');
    const remainingMatch = BigInt(program.matching_authorized_units) - BigInt(program.matching_used_units);
    const match = amount < remainingMatch ? amount : remainingMatch;
    const authorizedMatch = remainingAuthority - amount;
    const appliedMatch = match < authorizedMatch ? match : (authorizedMatch > 0n ? authorizedMatch : 0n);
    if (BigInt(earth.balance_units) < appliedMatch) throw new Error('Earth matching treasury is insufficient');
    const transaction = await postEconomicTransaction(tx, {
      correlationId: input.correlationId,
      kind: 'GLOBAL_PROGRAM_CONTRIBUTION',
      sourceType: 'HOUSE',
      sourceId: 'EARTH',
      rulesVersion: 'earth-programs-v2',
      entries: [
        { accountId: source.id, assetId: 1, deltaUnits: (-amount).toString() },
        { accountId: earth.id, assetId: 1, deltaUnits: (-appliedMatch).toString() },
        { accountId: sink.id, assetId: 1, deltaUnits: (amount + appliedMatch).toString() },
      ],
    }, clock);
    if (!transaction.created) return { ok: true, alreadyProcessed: true, correlationId: input.correlationId };
    const id = `PROGRAM-CONTRIBUTION-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query('INSERT INTO global_program_contributions (id, program_id, house_id, amount_units, matching_units, transaction_id, game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', [id, input.programId, input.houseId, amount.toString(), appliedMatch.toString(), transaction.transactionId, day, input.correlationId]);
    await tx.query('UPDATE global_programs SET funded_units = funded_units + $1, matching_used_units = matching_used_units + $2, status = \'ACTIVE\', recipient_account_id = $3 WHERE id = $4', [(amount + appliedMatch).toString(), appliedMatch.toString(), sink.id, input.programId]);
    await createGameEvent(tx, { id: `EARTH-PROGRAM-CONTRIBUTION-${id}`, category: 'GOVERNANCE', eventType: 'EARTH_GLOBAL_PROGRAM_PLAYER_FUNDED', gameDay: day, actorHumanId: input.humanId, subjectType: 'EARTH', subjectId: 'EARTH', title: 'House funded an EARTH program', details: { programId: input.programId, houseId: input.houseId, contributionUnits: amount.toString(), matchingUnits: appliedMatch.toString() }, correlationId: input.correlationId });
    return { ok: true, contributionId: id, programId: input.programId, contributionUnits: amount.toString(), matchingUnits: appliedMatch.toString(), fundedUnits: (BigInt(program.funded_units) + amount + appliedMatch).toString(), transactionId: transaction.transactionId, correlationId: input.correlationId };
  });
}

export async function settleGlobalProgramFunding(repository: PostgresRepository, programId: string, gameDay: number): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const program = (await tx.query<{ status: string; funding_deadline_game_day: number; funded_units: string; target_units: string }>('SELECT status, funding_deadline_game_day, funded_units::TEXT, target_units::TEXT FROM global_programs WHERE id = $1 FOR UPDATE', [programId])).rows[0];
    if (!program) throw new Error('Global program not found');
    if (['CANCELLED', 'COMPLETED'].includes(program.status)) return { ok: true, alreadyProcessed: true, programId, status: program.status };
    if (gameDay < Number(program.funding_deadline_game_day)) throw new Error('Global program funding deadline is not reached');
    const funded = BigInt(program.funded_units) >= BigInt(program.target_units);
    if (funded) {
      await tx.query("UPDATE global_program_contributions SET status = 'APPLIED' WHERE program_id = $1 AND status = 'ESCROWED'", [programId]);
      return { ok: true, programId, status: 'ACTIVE', contributionsApplied: true };
    }
    const rows = await tx.query<{ id: string; house_id: string; amount_units: string; matching_units: string; transaction_id: string }>(`SELECT c.id, c.house_id, c.amount_units::TEXT, c.matching_units::TEXT, c.transaction_id::TEXT FROM global_program_contributions c WHERE c.program_id = $1 AND c.status = 'ESCROWED' FOR UPDATE`, [programId]);
    const escrow = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.owner_type = 'SYSTEM' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' ORDER BY a.id LIMIT 1`)).rows[0];
    const earth = (await tx.query<{ id: string }>(`SELECT id::TEXT FROM economic_accounts WHERE owner_economic_id = 'ECON-EARTH-001' AND asset_id = 1 AND account_type = 'TREASURY' AND status = 'ACTIVE'`)).rows[0];
    if (!escrow || !earth) throw new Error('Program escrow or Earth treasury is unavailable for refund');
    for (const row of rows.rows) {
      const wallet = (await tx.query<{ id: string }>(`SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND a.asset_id = 1 AND a.account_type = 'WALLET' AND a.status = 'ACTIVE'`, [row.house_id])).rows[0];
      if (!wallet) throw new Error('House wallet is unavailable for refund');
      const refund = await postSettlementTransaction(tx, {
        correlationId: `program-refund:${row.id}`,
        gameDay,
        kind: 'GLOBAL_PROGRAM_REFUND',
        sourceType: 'EARTH',
        sourceId: 'HOUSE',
        rulesVersion: 'earth-programs-v2',
        entries: [
          { accountId: escrow.id, assetId: 1, deltaUnits: (-BigInt(row.amount_units) - BigInt(row.matching_units)).toString() },
          { accountId: wallet.id, assetId: 1, deltaUnits: row.amount_units },
          { accountId: earth.id, assetId: 1, deltaUnits: row.matching_units },
        ],
      });
      await tx.query("UPDATE global_program_contributions SET status = 'REFUNDED', refunded_game_day = $2, refund_transaction_id = $3 WHERE id = $1", [row.id, gameDay, refund.transactionId]);
    }
    await tx.query("UPDATE global_programs SET status = 'CANCELLED' WHERE id = $1", [programId]);
    return { ok: true, programId, status: 'CANCELLED', refundedContributions: rows.rows.length };
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
      if (BigInt(locked.progress_units) + actual >= BigInt(locked.target_units)) await tx.query(`INSERT INTO global_program_benefit_attributions (id, program_id, beneficiary_type, beneficiary_id, benefit_type, amount_units, effective_game_day, rules_version, correlation_id) VALUES ($1,$2,'EARTH','EARTH',$3,$4,$5,'global-program-benefits-v1',$6) ON CONFLICT (correlation_id) DO NOTHING`, [`PROGRAM-BENEFIT-${locked.id}`, locked.id, 'PLANETARY_PROGRAM_OUTPUT', actual.toString(), gameDay, `program-benefit:${locked.id}`]);
      advanced += 1;
    });
  }
  return { ok: true, gameDay, advanced };
}
