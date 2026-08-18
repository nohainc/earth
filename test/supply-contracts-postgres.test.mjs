import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listSupplyContracts,
  proposeSupplyContract,
  acceptSupplyContract,
  cancelSupplyContract,
  getContractDeliveryTicks,
} from '../cloudflare/src/supply-contracts-postgres.ts';

function createMockRepository() {
  const state = {
    negotiated_contracts: [],
    supply_contracts: [],
    contract_escrow_vaults: [],
    contract_delivery_ticks: [],
    account_balances: [
      { account_id: 'acc-buyer', owner_id: 'H-0044', currency: 'CREDIT', balance: '50000.00' },
      { account_id: 'acc-seller', owner_id: 'H-0012', currency: 'CREDIT', balance: '1000.00' },
    ],
    humans: [
      { id: 'H-0044', display_name: 'Amara Vance', life_status: 'active' },
      { id: 'H-0012', display_name: 'Dmitri Rostov', life_status: 'active' },
    ],
    world_state: [{ id: 'WORLD', game_day: 184 }],
    world_events: [],
    notifications: [],
    diplomatic_dispatches: [],
  };

  const repository = {
    query: async (sql, params = []) => {
      const trimmed = sql.trim();

      if (trimmed.includes('FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2')) {
        const found = state.negotiated_contracts.find((c) => c.proposer_id === params[0] && c.correlation_id === params[1]);
        return { rows: found ? [found] : [] };
      }

      if (trimmed.includes("FROM humans WHERE id = $1 AND life_status = 'active'")) {
        const found = state.humans.find((h) => h.id === params[0] && h.life_status === 'active');
        return { rows: found ? [found] : [] };
      }

      if (trimmed.includes("FROM world_state WHERE id = 'WORLD'")) {
        return { rows: state.world_state };
      }

      if (trimmed.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
        const found = state.account_balances.find((a) => a.owner_id === params[0] && a.currency === 'CREDIT');
        return { rows: found ? [found] : [] };
      }

      if (trimmed.startsWith('INSERT INTO negotiated_contracts')) {
        const row = {
          id: params[0],
          kind: 'capacity',
          proposer_id: params[1],
          counterparty_id: params[2],
          title: params[3],
          amount: params[4],
          status: 'proposed',
          starts_game_day: params[5],
          ends_game_day: params[6],
          correlation_id: params[7],
          created_at: new Date().toISOString(),
        };
        state.negotiated_contracts.push(row);
        return { rows: [row] };
      }

      if (trimmed.startsWith('INSERT INTO supply_contracts')) {
        const row = {
          contract_id: params[0],
          resource_type: params[1],
          daily_quantity: params[2],
          unit_price: params[3],
          total_days: params[4],
          delivered_days: 0,
          default_days: 0,
          consecutive_defaults: 0,
          max_consecutive_defaults: 3,
          escrow_total: params[5],
          escrow_remaining: params[6],
          penalty_per_default: params[7],
          last_settled_game_day: null,
          created_at: new Date().toISOString(),
        };
        state.supply_contracts.push(row);
        return { rows: [row] };
      }

      if (trimmed.startsWith('INSERT INTO contract_escrow_vaults')) {
        const row = {
          id: params[0],
          contract_id: params[1],
          buyer_id: params[2],
          seller_id: params[3],
          locked_amount: params[4],
          released_amount: '0.00',
          refunded_amount: '0.00',
          penalty_paid: '0.00',
          status: params[5],
          updated_at: new Date().toISOString(),
        };
        state.contract_escrow_vaults.push(row);
        return { rows: [row] };
      }

      if (trimmed.startsWith('INSERT INTO world_events')) {
        state.world_events.push({ id: params[0], game_day: params[1], event_type: params[2] });
        return { rows: [] };
      }

      if (trimmed.startsWith('INSERT INTO diplomatic_dispatches')) {
        state.diplomatic_dispatches.push({ id: params[0], sender_human_id: params[1], recipient_human_id: params[2], subject: params[3] });
        return { rows: [] };
      }

      if (trimmed.startsWith('INSERT INTO notifications')) {
        state.notifications.push({ id: params[0], human_id: params[1] });
        return { rows: [] };
      }

      if (trimmed.includes('FROM negotiated_contracts WHERE id = $1')) {
        const found = state.negotiated_contracts.find((c) => c.id === params[0]);
        return { rows: found ? [found] : [] };
      }

      if (trimmed.includes('FROM supply_contracts WHERE contract_id = $1')) {
        const found = state.supply_contracts.find((s) => s.contract_id === params[0]);
        return { rows: found ? [found] : [] };
      }

      if (trimmed.includes('FROM contract_escrow_vaults WHERE contract_id = $1')) {
        const found = state.contract_escrow_vaults.find((v) => v.contract_id === params[0]);
        return { rows: found ? [found] : [] };
      }

      if (trimmed.startsWith('UPDATE account_balances SET balance = $1 WHERE account_id = $2')) {
        const acc = state.account_balances.find((a) => a.account_id === params[1]);
        if (acc) acc.balance = params[0];
        return { rows: [] };
      }

      if (trimmed.startsWith("UPDATE negotiated_contracts SET status = 'accepted'")) {
        const found = state.negotiated_contracts.find((c) => c.id === params[1]);
        if (found) {
          found.status = 'accepted';
          found.accepted_game_day = params[0];
        }
        return { rows: [] };
      }

      if (trimmed.startsWith("UPDATE negotiated_contracts SET status = 'cancelled'")) {
        const found = state.negotiated_contracts.find((c) => c.id === params[0]);
        if (found) found.status = 'cancelled';
        return { rows: [] };
      }

      if (trimmed.startsWith('UPDATE contract_escrow_vaults')) {
        const found = state.contract_escrow_vaults.find((v) => v.id === params[params.length - 1]);
        if (found) found.status = 'locked';
        return { rows: [] };
      }

      if (trimmed.includes('FROM contract_delivery_ticks WHERE contract_id = $1')) {
        const ticks = state.contract_delivery_ticks.filter((t) => t.contract_id === params[0]);
        return { rows: ticks };
      }

      if (trimmed.includes('FROM negotiated_contracts nc')) {
        const joined = state.negotiated_contracts.map((nc) => {
          const sc = state.supply_contracts.find((s) => s.contract_id === nc.id) || {};
          const ev = state.contract_escrow_vaults.find((v) => v.contract_id === nc.id) || {};
          return {
            contract_id: nc.id,
            title: nc.title,
            proposer_id: nc.proposer_id,
            counterparty_id: nc.counterparty_id,
            status: nc.status,
            ...sc,
            vault_id: ev.id,
            vault_locked_amount: ev.locked_amount,
            vault_status: ev.status,
          };
        });
        return { rows: joined };
      }

      return { rows: [] };
    },
    transaction: async (fn) => fn(repository),
  };

  return { repository, state };
}

test('supply contracts postgres domain logic: propose, list, accept, cancel', async () => {
  const { repository, state } = createMockRepository();

  // 1. Propose Supply Contract
  const proposal = await proposeSupplyContract(repository, {
    proposerId: 'H-0044',
    counterpartyId: 'H-0012',
    proposerRole: 'buyer',
    resourceType: 'energy',
    dailyQuantity: 50,
    unitPrice: 14.5,
    totalDays: 30,
    penaltyPerDefault: 100,
    correlationId: 'SUPPLY-CORR-1',
  });

  assert.equal(proposal.ok, true);
  assert.equal(proposal.status, 'proposed');
  assert.equal(proposal.totalAmount, '21750.00');

  // Verify created structures
  assert.equal(state.negotiated_contracts.length, 1);
  assert.equal(state.supply_contracts.length, 1);
  assert.equal(state.contract_escrow_vaults.length, 1);
  assert.equal(state.diplomatic_dispatches.length, 1);

  // 2. List Supply Contracts
  const list = await listSupplyContracts(repository, 'H-0044');
  assert.equal(list.ok, true);
  assert.equal(list.supplyContracts.length, 1);
  assert.equal(list.supplyContracts[0].resource_type, 'energy');

  // 3. Accept Contract (by counterparty H-0012)
  const accepted = await acceptSupplyContract(repository, proposal.contractId, 'H-0012');
  assert.equal(accepted.ok, true);
  assert.equal(accepted.status, 'accepted');
  assert.equal(accepted.escrowLocked, '21750.00');

  // Verify buyer credits were deducted to lock escrow
  const buyerAcc = state.account_balances.find((a) => a.owner_id === 'H-0044');
  assert.equal(buyerAcc.balance, '28250.00'); // 50000 - 21750

  // 4. Cancel / Terminate Contract & Verify Refund
  const cancelled = await cancelSupplyContract(repository, proposal.contractId, 'H-0044');
  assert.equal(cancelled.ok, true);
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.refundedAmount, '21750.00');

  // Buyer should be refunded
  assert.equal(buyerAcc.balance, '50000.00');
});
