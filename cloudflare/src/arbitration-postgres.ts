import type { PostgresRepository } from './repository';

export async function resolveContractDispute(
  repository: PostgresRepository,
  input: { contractId: string; resolverId: string; outcome: 'uphold' | 'void'; resolution: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const authority = await tx.query("SELECT id FROM role_assignments WHERE role_id = 'ROLE-OUC-DELEGATE' AND human_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') UNION ALL SELECT id FROM authority_delegations WHERE role_id = 'ROLE-OUC-DELEGATE' AND delegate_id = $1 AND status = 'active' AND ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [input.resolverId]);
    if (!authority.rows[0]) throw new Error('OUC arbitration authority is required');
    const contract = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; amount: string }>('SELECT id, proposer_id, counterparty_id, amount FROM negotiated_contracts WHERE id = $1 FOR UPDATE', [input.contractId]);
    if (!contract.rows[0]) throw new Error('Contract not found');
    const dispute = await tx.query<{ id: string }>("SELECT id FROM contract_disputes WHERE contract_id = $1 AND status = 'open' FOR UPDATE", [input.contractId]);
    if (!dispute.rows[0]) throw new Error('Open dispute not found');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query("UPDATE contract_disputes SET status = 'resolved', outcome = $1, resolved_by = $2, resolved_game_day = $3, resolution = $4 WHERE id = $5 AND status = 'open'", [input.outcome, input.resolverId, day, input.resolution, dispute.rows[0].id]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'arbitration.resolved', 'A contract dispute was resolved', JSON.stringify({ disputeId: dispute.rows[0].id, contractId: input.contractId, outcome: input.outcome, resolvedBy: input.resolverId })]);
    if (input.outcome === 'void') {
      const payer = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [contract.rows[0].counterparty_id]);
      const receiver = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [contract.rows[0].proposer_id]);
      const amount = Number(contract.rows[0].amount);
      if (!payer.rows[0] || !receiver.rows[0] || Number(payer.rows[0].balance) < amount) throw new Error('Counterparty cannot fund the arbitration refund');
      const refundId = `ARBITRATION-REFUND-${input.contractId}`;
      await tx.query("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = $1 AND status IN ('accepted','completed')", [input.contractId]);
      await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [amount, payer.rows[0].account_id]);
      await tx.query('UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2', [amount, receiver.rows[0].account_id]);
      await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT (id) DO NOTHING', [refundId, day, payer.rows[0].account_id, receiver.rows[0].account_id, amount, 'CREDIT', 'contract_arbitration_refund', input.contractId, 'arbitration-v1', refundId]);
      await tx.query("UPDATE business_financials SET operating_costs = GREATEST(0, operating_costs - $1), profit = profit + $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [amount, day, contract.rows[0].proposer_id]);
      await tx.query("UPDATE business_financials SET revenue = GREATEST(0, revenue - $1), profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [amount, day, contract.rows[0].counterparty_id]);
    }
    return { ok: true, outcome: input.outcome, dispute: (await tx.query('SELECT * FROM contract_disputes WHERE id = $1', [dispute.rows[0].id])).rows[0] };
  });
}
