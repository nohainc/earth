import type { PostgresRepository } from './repository';

export async function acceptContract(repository: PostgresRepository, contractId: string, actorId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const contract = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; amount: string; status: string; title: string }>('SELECT id, proposer_id, counterparty_id, amount, status, title FROM negotiated_contracts WHERE id = $1 FOR UPDATE', [contractId]);
    if (!contract.rows[0]) throw new Error('Contract not found');
    const row = contract.rows[0];
    if (row.counterparty_id !== actorId) throw new Error('Only the counterparty may accept this contract');
    if (row.status !== 'proposed') return { ok: true, alreadyProcessed: row.status === 'accepted', status: row.status, contractId };
    const payer = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [row.proposer_id]);
    const receiver = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [row.counterparty_id]);
    const amount = Number(row.amount);
    if (!payer.rows[0] || !receiver.rows[0] || Number(payer.rows[0].balance) < amount) throw new Error('Proposer has insufficient Credits to settle this contract');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const correlationId = `CONTRACT-${row.id}`;
    await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [amount, payer.rows[0].account_id]);
    await tx.query('UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2', [amount, receiver.rows[0].account_id]);
    await tx.query("UPDATE negotiated_contracts SET status = 'accepted', accepted_game_day = $1 WHERE id = $2 AND status = 'proposed'", [day, row.id]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [correlationId, day, payer.rows[0].account_id, receiver.rows[0].account_id, amount, 'CREDIT', 'contract_payment', row.id, 'contracts-v1', correlationId]);
    await tx.query("UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [amount, day, row.proposer_id]);
    await tx.query("UPDATE business_financials SET revenue = revenue + $1, profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [amount, day, row.counterparty_id]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'contract.accepted', 'A negotiated contract was accepted', JSON.stringify({ contractId: row.id, amount })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), row.proposer_id, 'contract', 'Contract accepted', `${row.title} was accepted and ${amount} Credits were settled.`, row.id]);
    return { ok: true, status: 'accepted', contract: (await tx.query('SELECT * FROM negotiated_contracts WHERE id = $1', [row.id])).rows[0] };
  });
}

export async function createContract(repository: PostgresRepository, input: { proposerId: string; kind: string; counterpartyId: string; title: string; terms: Record<string, unknown>; amount: number; durationDays: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2', [input.proposerId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contract: prior.rows[0], correlationId: input.correlationId };
    const counterparty = await tx.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.counterpartyId]);
    if (!counterparty.rows[0]) throw new Error('An active counterparty Human is required');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const contractId = 'CON-' + crypto.randomUUID().slice(0, 8).toUpperCase();
    await tx.query('INSERT INTO negotiated_contracts (id, kind, proposer_id, counterparty_id, title, terms_json, amount, starts_game_day, ends_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [contractId, input.kind, input.proposerId, input.counterpartyId, input.title, JSON.stringify(input.terms), input.amount, day, day + input.durationDays, input.correlationId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'contract.proposed', 'A negotiated contract was proposed', JSON.stringify({ contractId, kind: input.kind, proposer: input.proposerId, counterparty: input.counterpartyId })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.counterpartyId, 'contract', 'Contract proposal received', input.title + ' was proposed for your acceptance.', contractId]);
    return { ok: true, contract: (await tx.query('SELECT * FROM negotiated_contracts WHERE id = $1', [contractId])).rows[0], correlationId: input.correlationId };
  });
}

export async function cancelContract(repository: PostgresRepository, contractId: string, actorId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const contract = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; status: string }>('SELECT id, proposer_id, counterparty_id, status FROM negotiated_contracts WHERE id = $1 FOR UPDATE', [contractId]);
    if (!contract.rows[0]) throw new Error('Contract not found');
    if (contract.rows[0].proposer_id !== actorId && contract.rows[0].counterparty_id !== actorId) throw new Error('Only a contract party may cancel');
    if (contract.rows[0].status !== 'proposed') throw new Error('Only a proposed contract can be cancelled');
    await tx.query("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = $1 AND status = 'proposed'", [contractId]);
    return { ok: true, status: 'cancelled', contractId };
  });
}

export async function openDispute(repository: PostgresRepository, input: { contractId: string; claimantId: string; reason: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const contract = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; title: string; status: string }>('SELECT id, proposer_id, counterparty_id, title, status FROM negotiated_contracts WHERE id = $1 FOR UPDATE', [input.contractId]);
    if (!contract.rows[0]) throw new Error('Contract not found');
    if (input.claimantId !== contract.rows[0].proposer_id && input.claimantId !== contract.rows[0].counterparty_id) throw new Error('Only a contract party may open a dispute');
    if (!['accepted', 'completed'].includes(contract.rows[0].status)) throw new Error('Only an accepted or completed contract can be disputed');
    const existing = await tx.query("SELECT * FROM contract_disputes WHERE contract_id = $1 AND status = 'open'", [input.contractId]);
    if (existing.rows[0]) return { ok: true, alreadyOpen: true, dispute: existing.rows[0] };
    const disputeId = 'DISPUTE-' + crypto.randomUUID().slice(0, 8).toUpperCase();
    await tx.query('INSERT INTO contract_disputes (id, contract_id, claimant_id, respondent_id, reason) VALUES ($1,$2,$3,$4,$5)', [disputeId, input.contractId, input.claimantId, input.claimantId === contract.rows[0].proposer_id ? contract.rows[0].counterparty_id : contract.rows[0].proposer_id, input.reason]);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), Number(world.rows[0]?.game_day ?? 0), 'arbitration.opened', 'A contract dispute was opened', JSON.stringify({ disputeId, contractId: input.contractId })]);
    return { ok: true, dispute: (await tx.query('SELECT * FROM contract_disputes WHERE id = $1', [disputeId])).rows[0] };
  });
}
