import type { PostgresRepository } from './repository.ts';
import { MARKET_ASSET_IDS } from './market-model.ts';
import { postSettlementBatch, closeEscrowAccount } from './market-escrow.ts';
import { calculateQuoteUnits } from './market-units.ts';

type Effect = { accountId: string; assetId: number; delta: bigint; reason: string };

/** Settle all expired delivery futures; one atomic posting per instrument. */
export async function settleDueDeliveryFutures(
  repository: PostgresRepository,
  safeProcessedGameDay: number,
  workBudgetMs = 10_000,
): Promise<number> {
  const startedAt = Date.now();
  const expiryCutoff = safeProcessedGameDay * 1440;
  const instruments = await repository.query<{ id: string; base_asset_id: number; expiry_total_game_minute: string }>(
    `SELECT id, base_asset_id, expiry_total_game_minute
       FROM market_instruments
      WHERE instrument_type = 'DELIVERY_FUTURE' AND status = 'active'
        AND expiry_total_game_minute <= $1
      ORDER BY expiry_total_game_minute, id`,
    [expiryCutoff],
  );
  let settled = 0;

  for (const instrument of instruments.rows) {
    if (Date.now() - startedAt >= workBudgetMs) break;
    await repository.transaction(async (tx) => {
      const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD'");
      const day = Number(world.rows[0]?.game_day ?? safeProcessedGameDay);
      const minute = Number(world.rows[0]?.game_minute ?? 0);
      const locked = await tx.query<{ id: string; base_asset_id: number; expiry_total_game_minute: string }>(
        `UPDATE market_instruments
            SET status = 'closed', updated_at = CURRENT_TIMESTAMP
          WHERE id = $1 AND status = 'active'
        RETURNING id, base_asset_id, expiry_total_game_minute`,
        [instrument.id],
      );
      if (!locked.rows[0]) return;

      const orders = await tx.query<{ id: string; owner_economic_id: string; side: string; escrow_account_id: string; status: string }>(
        `SELECT id, owner_economic_id, side, escrow_account_id, status
           FROM market_orders
          WHERE instrument_id = $1 AND escrow_account_id IS NOT NULL
          FOR UPDATE`,
        [instrument.id],
      );
      const obligations = await tx.query<{
        id: string; long_owner_economic_id: string; short_owner_economic_id: string;
        quantity_units: string; delivery_price_units: string;
        long_escrow_account_id: string; short_escrow_account_id: string;
      }>(
        `SELECT id, long_owner_economic_id, short_owner_economic_id, quantity_units, delivery_price_units,
                long_escrow_account_id, short_escrow_account_id
           FROM derivative_obligations
          WHERE instrument_id = $1 AND status = 'open'
          FOR UPDATE`,
        [instrument.id],
      );
      const ownerIds = new Set<string>();
      for (const order of orders.rows) ownerIds.add(String(order.owner_economic_id));
      for (const obligation of obligations.rows) {
        ownerIds.add(String(obligation.long_owner_economic_id));
        ownerIds.add(String(obligation.short_owner_economic_id));
      }
      const accounts = await tx.query<{ id: string; owner_economic_id: string; asset_id: number }>(
        `SELECT DISTINCT ON (owner_economic_id, asset_id)
                id::TEXT, owner_economic_id::TEXT, asset_id
           FROM economic_accounts
          WHERE owner_economic_id = ANY($1::BIGINT[]) AND asset_id = ANY($2::SMALLINT[])
            AND status = 'active' AND is_default_settlement
          ORDER BY owner_economic_id, asset_id, id`,
        [[...ownerIds], [MARKET_ASSET_IDS.CREDIT, instrument.base_asset_id]],
      );
      const destination = new Map(accounts.rows.map((account) => [`${account.owner_economic_id}:${account.asset_id}`, account.id]));
      const effects = new Map<string, Effect>();
      const add = (accountId: string, assetId: number, delta: bigint, reason: string) => {
        if (delta === 0n) return;
        const existing = effects.get(`${accountId}:${assetId}`);
        if (existing) existing.delta += delta;
        else effects.set(`${accountId}:${assetId}`, { accountId, assetId, delta, reason });
      };
      const escrowIds = new Set<string>();
      for (const order of orders.rows) escrowIds.add(String(order.escrow_account_id));
      for (const obligation of obligations.rows) {
        const quote = calculateQuoteUnits(BigInt(obligation.quantity_units), BigInt(obligation.delivery_price_units));
        const longWallet = destination.get(`${obligation.short_owner_economic_id}:${MARKET_ASSET_IDS.CREDIT}`);
        const longInventory = destination.get(`${obligation.long_owner_economic_id}:${instrument.base_asset_id}`);
        if (!longWallet || !longInventory) throw new Error('Delivery-future settlement account is missing');
        add(obligation.long_escrow_account_id, MARKET_ASSET_IDS.CREDIT, -quote, 'future_delivery');
        add(longWallet, MARKET_ASSET_IDS.CREDIT, quote, 'future_delivery');
        add(obligation.short_escrow_account_id, instrument.base_asset_id, -BigInt(obligation.quantity_units), 'future_delivery');
        add(longInventory, instrument.base_asset_id, BigInt(obligation.quantity_units), 'future_delivery');
        escrowIds.add(obligation.long_escrow_account_id);
        escrowIds.add(obligation.short_escrow_account_id);
      }

      const escrowBalances = await tx.query<{ id: string; balance: string; owner_economic_id: string; asset_id: number }>(
        `SELECT a.id::TEXT, a.balance::TEXT, a.owner_economic_id::TEXT, a.asset_id
           FROM economic_accounts a
          WHERE a.id = ANY($1::BIGINT[]) AND a.account_type = 6
          FOR UPDATE`,
        [[...escrowIds]],
      );
      for (const escrow of escrowBalances.rows) {
        const remaining = BigInt(escrow.balance) + (effects.get(`${escrow.id}:${escrow.asset_id}`)?.delta ?? 0n);
        if (remaining < 0n) throw new Error(`Future escrow is undercollateralized: ${escrow.id}`);
        const ownerAccount = destination.get(`${escrow.owner_economic_id}:${escrow.asset_id}`);
        if (!ownerAccount) throw new Error('Future escrow refund account is missing');
        add(escrow.id, escrow.asset_id, -remaining, 'future_expiry_refund');
        add(ownerAccount, escrow.asset_id, remaining, 'future_expiry_refund');
      }

      const entries = [...effects.values()];
      const posted = entries.length >= 2
        ? await postSettlementBatch(tx, day, `derivative-expiry:${instrument.id}`, instrument.id, entries)
        : { transactionId: null, created: true };
      if (!posted.created) return;
      await tx.query(`UPDATE derivative_obligations
                         SET status = 'settled', settlement_transaction_id = $2,
                             settled_game_day = $3, settled_game_minute = $4
                       WHERE instrument_id = $1 AND status = 'open'`, [instrument.id, posted.transactionId, day, minute]);
      await tx.query(`UPDATE market_orders
                         SET status = CASE WHEN status IN ('open', 'partial') THEN 'cancelled' ELSE status END,
                             reserved_quote_units = 0, reserved_base_units = 0
                       WHERE instrument_id = $1`, [instrument.id]);
      for (const escrowId of escrowIds) await closeEscrowAccount(tx, escrowId, instrument.id);
      await tx.query("UPDATE market_instruments SET status = 'settled', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [instrument.id]);
      settled += 1;
    });
  }
  return settled;
}
