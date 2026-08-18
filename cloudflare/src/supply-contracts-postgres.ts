import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { toNanoMarkup } from './nano-markup.ts';

export interface SupplyContractRow {
  contract_id: string;
  resource_type: 'food' | 'energy' | 'material' | 'compute';
  daily_quantity: string;
  unit_price: string;
  total_days: number;
  delivered_days: number;
  default_days: number;
  max_consecutive_defaults: number;
  consecutive_defaults: number;
  escrow_total: string;
  escrow_remaining: string;
  penalty_per_default: string;
  last_settled_game_day: number | null;
  created_at: string;
  title?: string;
  proposer_id?: string;
  counterparty_id?: string;
  status?: string;
}

export interface ContractEscrowVaultRow {
  id: string;
  contract_id: string;
  buyer_id: string;
  seller_id: string;
  locked_amount: string;
  released_amount: string;
  refunded_amount: string;
  penalty_paid: string;
  status: string;
  updated_at: string;
}

export async function listSupplyContracts(
  repository: PostgresRepository,
  actorId: string,
): Promise<{ ok: boolean; supplyContracts: Record<string, unknown>[] }> {
  const result = await repository.query<Record<string, unknown>>(
    `SELECT 
       nc.id AS contract_id,
       nc.title,
       nc.proposer_id,
       nc.counterparty_id,
       nc.status,
       nc.starts_game_day,
       nc.ends_game_day,
       nc.created_at,
       hp.display_name AS proposer_display_name,
       hc.display_name AS counterparty_display_name,
       sc.resource_type,
       sc.daily_quantity,
       sc.unit_price,
       sc.total_days,
       sc.delivered_days,
       sc.default_days,
       sc.consecutive_defaults,
       sc.max_consecutive_defaults,
       sc.escrow_total,
       sc.escrow_remaining,
       sc.penalty_per_default,
       sc.last_settled_game_day,
       ev.id AS vault_id,
       ev.locked_amount AS vault_locked_amount,
       ev.released_amount AS vault_released_amount,
       ev.refunded_amount AS vault_refunded_amount,
       ev.penalty_paid AS vault_penalty_paid,
       ev.status AS vault_status
     FROM negotiated_contracts nc
     JOIN supply_contracts sc ON sc.contract_id = nc.id
     LEFT JOIN contract_escrow_vaults ev ON ev.contract_id = nc.id
     LEFT JOIN humans hp ON hp.id = nc.proposer_id
     LEFT JOIN humans hc ON hc.id = nc.counterparty_id
     WHERE nc.proposer_id = $1 OR nc.counterparty_id = $1
     ORDER BY nc.created_at DESC LIMIT 50`,
    [actorId],
  );

  return {
    ok: true,
    supplyContracts: result.rows,
  };
}

export async function proposeSupplyContract(
  repository: PostgresRepository,
  input: {
    proposerId: string;
    counterpartyId: string;
    proposerRole: 'buyer' | 'seller';
    resourceType: 'food' | 'energy' | 'material' | 'compute';
    dailyQuantity: number;
    unitPrice: number;
    totalDays: number;
    penaltyPerDefault?: number;
    title?: string;
    correlationId: string;
  },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (input.proposerId === input.counterpartyId) {
      throw new Error('Proposer and counterparty must be distinct');
    }
    if (input.dailyQuantity <= 0 || input.unitPrice <= 0 || input.totalDays <= 0) {
      throw new Error('Quantity, unit price, and duration must be positive values');
    }

    const prior = await tx.query(
      'SELECT id FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2',
      [input.proposerId, input.correlationId],
    );
    if (prior.rows[0]) {
      return { ok: true, alreadyProcessed: true, contractId: prior.rows[0].id };
    }

    const counterparty = await tx.query(
      "SELECT id, display_name FROM humans WHERE id = $1 AND life_status = 'active'",
      [input.counterpartyId],
    );
    if (!counterparty.rows[0]) {
      throw new Error('Active counterparty Human is required');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    const buyerId = input.proposerRole === 'buyer' ? input.proposerId : input.counterpartyId;
    const sellerId = input.proposerRole === 'seller' ? input.proposerId : input.counterpartyId;

    const totalCents = BigInt(Math.round(input.dailyQuantity * 100)) *
      BigInt(Math.round(input.unitPrice * 100)) *
      BigInt(input.totalDays) / 100n;
    const totalAmount = centsToMoney(totalCents);
    const penaltyAmount = centsToMoney(BigInt(Math.round((input.penaltyPerDefault ?? 0) * 100)));

    // Verify buyer has sufficient Credits for the escrow lock
    const buyerBalanceRow = await tx.query<{ balance: string }>(
      "SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'",
      [buyerId],
    );
    const buyerBalance = moneyToCents(buyerBalanceRow.rows[0]?.balance ?? '0');
    if (buyerBalance < totalCents) {
      throw new Error(`Buyer requires ${totalAmount} Credits to establish supply contract escrow`);
    }

    const contractId = 'CTR-' + crypto.randomUUID().slice(0, 8).toUpperCase();
    const vaultId = 'VAULT-' + contractId;
    const title = input.title ?? `${input.dailyQuantity} ${input.resourceType.toUpperCase()} / Day Supply Agreement`;

    // 1. Insert Base Negotiated Contract
    await tx.query(
      `INSERT INTO negotiated_contracts 
         (id, kind, proposer_id, counterparty_id, title, amount, status, starts_game_day, ends_game_day, correlation_id)
       VALUES ($1, 'capacity', $2, $3, $4, $5, 'proposed', $6, $7, $8)`,
      [contractId, input.proposerId, input.counterpartyId, title, totalAmount, day, day + input.totalDays, input.correlationId],
    );

    // 2. Insert Supply Contract Details
    await tx.query(
      `INSERT INTO supply_contracts 
         (contract_id, resource_type, daily_quantity, unit_price, total_days, escrow_total, escrow_remaining, penalty_per_default)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        contractId,
        input.resourceType,
        centsToMoney(BigInt(Math.round(input.dailyQuantity * 100))),
        centsToMoney(BigInt(Math.round(input.unitPrice * 100))),
        input.totalDays,
        totalAmount,
        totalAmount,
        penaltyAmount,
      ],
    );

    // 3. Pre-create Escrow Vault record
    await tx.query(
      `INSERT INTO contract_escrow_vaults 
         (id, contract_id, buyer_id, seller_id, locked_amount, status)
       VALUES ($1, $2, $3, $4, $5, 'locked')`,
      [vaultId, contractId, buyerId, sellerId, totalAmount],
    );

    // 4. Record World Event & Diplomatic Dispatch
    await tx.query(
      `INSERT INTO world_events (id, game_day, event_type, title, details)
       VALUES ($1, $2, 'supply_contract.proposed', 'A recurring supply agreement was proposed', $3)`,
      [
        crypto.randomUUID(),
        day,
        toNanoMarkup({
          contractId,
          buyerId,
          sellerId,
          resourceType: input.resourceType,
          dailyQuantity: input.dailyQuantity,
          unitPrice: input.unitPrice,
          totalAmount,
        }),
      ],
    );

    await tx.query(
      `INSERT INTO diplomatic_dispatches 
         (id, sender_human_id, recipient_human_id, subject, body, status, game_day, game_minute, dispatch_type, action_payload)
       VALUES ($1, $2, $3, $4, $5, 'unread', $6, 0, 'contract_offer', $7)`,
      [
        'MAIL-' + crypto.randomUUID().slice(0, 8).toUpperCase(),
        input.proposerId,
        input.counterpartyId,
        `Tender: ${title}`,
        `We have submitted a binding supply contract proposal for ${input.dailyQuantity} units of ${input.resourceType.toUpperCase()} per game day at ${input.unitPrice} CR/unit for ${input.totalDays} game days. Total Escrow: ${totalAmount} CR.`,
        day,
        toNanoMarkup({
          contractId,
          resourceType: input.resourceType,
          dailyQuantity: input.dailyQuantity,
          unitPrice: input.unitPrice,
          totalDays: input.totalDays,
          totalAmount,
        }),
      ],
    );

    return {
      ok: true,
      contractId,
      vaultId,
      totalAmount,
      status: 'proposed',
    };
  });
}

export async function acceptSupplyContract(
  repository: PostgresRepository,
  contractId: string,
  actorId: string,
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const contract = await tx.query<{
      id: string;
      proposer_id: string;
      counterparty_id: string;
      status: string;
      title: string;
      amount: string;
    }>(
      'SELECT id, proposer_id, counterparty_id, status, title, amount FROM negotiated_contracts WHERE id = $1 FOR UPDATE',
      [contractId],
    );
    if (!contract.rows[0]) throw new Error('Contract not found');
    const row = contract.rows[0];

    if (row.counterparty_id !== actorId) {
      throw new Error('Only the recipient counterparty may accept this contract proposal');
    }
    if (row.status !== 'proposed') {
      return { ok: true, alreadyProcessed: true, status: row.status, contractId };
    }

    const supplyRow = await tx.query<SupplyContractRow>(
      'SELECT * FROM supply_contracts WHERE contract_id = $1 FOR UPDATE',
      [contractId],
    );
    if (!supplyRow.rows[0]) throw new Error('Supply contract terms not found');
    const supply = supplyRow.rows[0];

    const vaultRow = await tx.query<ContractEscrowVaultRow>(
      'SELECT * FROM contract_escrow_vaults WHERE contract_id = $1 FOR UPDATE',
      [contractId],
    );
    if (!vaultRow.rows[0]) throw new Error('Escrow vault not initialized');
    const vault = vaultRow.rows[0];

    const buyerId = vault.buyer_id;
    const sellerId = vault.seller_id;
    const requiredCents = moneyToCents(supply.escrow_total);

    // Verify and Lock buyer funds
    const buyerAccount = await tx.query<{ account_id: string; balance: string }>(
      "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
      [buyerId],
    );
    if (!buyerAccount.rows[0] || moneyToCents(buyerAccount.rows[0].balance) < requiredCents) {
      throw new Error('Buyer has insufficient Credits to lock required escrow funds');
    }

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 1);

    // Deduct total escrow amount from buyer's spendable balance into locked state
    const newBuyerBalance = centsToMoney(moneyToCents(buyerAccount.rows[0].balance) - requiredCents);
    await tx.query(
      'UPDATE account_balances SET balance = $1 WHERE account_id = $2',
      [newBuyerBalance, buyerAccount.rows[0].account_id],
    );

    // Update contract & vault
    await tx.query(
      "UPDATE negotiated_contracts SET status = 'accepted', accepted_game_day = $1 WHERE id = $2",
      [day, contractId],
    );
    await tx.query(
      "UPDATE contract_escrow_vaults SET status = 'locked', updated_at = CURRENT_TIMESTAMP WHERE id = $1",
      [vault.id],
    );

    // Notify parties
    await tx.query(
      `INSERT INTO world_events (id, game_day, event_type, title, details)
       VALUES ($1, $2, 'supply_contract.accepted', 'Supply agreement active and escrow locked', $3)`,
      [
        crypto.randomUUID(),
        day,
        toNanoMarkup({ contractId, buyerId, sellerId, escrowLocked: supply.escrow_total }),
      ],
    );

    await tx.query(
      `INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id)
       VALUES ($1, $2, 'contract', 'Supply Contract Active', $3, $4),
              ($5, $6, 'contract', 'Supply Contract Active', $7, $4)`,
      [
        crypto.randomUUID(),
        row.proposer_id,
        `${row.title} was accepted. ${supply.escrow_total} Credits locked into Escrow Vault.`,
        contractId,
        crypto.randomUUID(),
        row.counterparty_id,
        `${row.title} is now active. Daily deliveries will begin on the next game day.`,
        contractId,
      ],
    );

    return {
      ok: true,
      status: 'accepted',
      contractId,
      escrowLocked: supply.escrow_total,
    };
  });
}

export async function cancelSupplyContract(
  repository: PostgresRepository,
  contractId: string,
  actorId: string,
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const contract = await tx.query<{
      id: string;
      proposer_id: string;
      counterparty_id: string;
      status: string;
      title: string;
    }>(
      'SELECT id, proposer_id, counterparty_id, status, title FROM negotiated_contracts WHERE id = $1 FOR UPDATE',
      [contractId],
    );
    if (!contract.rows[0]) throw new Error('Contract not found');
    const row = contract.rows[0];

    if (row.proposer_id !== actorId && row.counterparty_id !== actorId) {
      throw new Error('Only a contract party may cancel or terminate this contract');
    }

    const supplyRow = await tx.query<SupplyContractRow>(
      'SELECT * FROM supply_contracts WHERE contract_id = $1 FOR UPDATE',
      [contractId],
    );
    const vaultRow = await tx.query<ContractEscrowVaultRow>(
      'SELECT * FROM contract_escrow_vaults WHERE contract_id = $1 FOR UPDATE',
      [contractId],
    );

    // If accepted and escrow exists, refund remaining balance back to buyer
    let refundedAmount = '0.00';
    if (row.status === 'accepted' && supplyRow.rows[0] && vaultRow.rows[0]) {
      const remainingCents = moneyToCents(supplyRow.rows[0].escrow_remaining);
      if (remainingCents > 0n) {
        const buyerAccount = await tx.query<{ account_id: string; balance: string }>(
          "SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE",
          [vaultRow.rows[0].buyer_id],
        );
        if (buyerAccount.rows[0]) {
          const newBal = centsToMoney(moneyToCents(buyerAccount.rows[0].balance) + remainingCents);
          await tx.query('UPDATE account_balances SET balance = $1 WHERE account_id = $2', [
            newBal,
            buyerAccount.rows[0].account_id,
          ]);
          refundedAmount = centsToMoney(remainingCents);
        }
      }

      await tx.query(
        "UPDATE contract_escrow_vaults SET refunded_amount = refunded_amount + $1, status = 'refunded', updated_at = CURRENT_TIMESTAMP WHERE id = $2",
        [refundedAmount, vaultRow.rows[0].id],
      );
      await tx.query(
        "UPDATE supply_contracts SET escrow_remaining = '0.00' WHERE contract_id = $1",
        [contractId],
      );
    }

    await tx.query("UPDATE negotiated_contracts SET status = 'cancelled' WHERE id = $1", [contractId]);

    return {
      ok: true,
      status: 'cancelled',
      contractId,
      refundedAmount,
    };
  });
}

export async function getContractDeliveryTicks(
  repository: PostgresRepository,
  contractId: string,
  actorId: string,
): Promise<{ ok: boolean; ticks: Record<string, unknown>[] }> {
  const contract = await repository.query<{ proposer_id: string; counterparty_id: string }>(
    'SELECT proposer_id, counterparty_id FROM negotiated_contracts WHERE id = $1',
    [contractId],
  );
  if (!contract.rows[0]) throw new Error('Contract not found');
  if (contract.rows[0].proposer_id !== actorId && contract.rows[0].counterparty_id !== actorId) {
    throw new Error('Access denied');
  }

  const result = await repository.query<Record<string, unknown>>(
    'SELECT * FROM contract_delivery_ticks WHERE contract_id = $1 ORDER BY game_day DESC LIMIT 50',
    [contractId],
  );

  return {
    ok: true,
    ticks: result.rows,
  };
}
