import type { PostgresRepository } from './repository.ts';
import { getAuthoritativeGameTime } from './game-clock.ts';

export interface OHLCSnapshot {
  id: string;
  commodity: string;
  game_day: number;
  open_price: string | number;
  high_price: string | number;
  low_price: string | number;
  close_price: string | number;
  volume: string | number;
}

export interface FuturesContract {
  id: string;
  seller_human_id: string;
  seller_name?: string;
  buyer_human_id: string | null;
  buyer_name?: string;
  commodity: string;
  contract_size: string | number;
  strike_price: string | number;
  expiry_game_day: number;
  collateral_locked: string | number;
  premium_paid: string | number;
  status: 'open' | 'matched' | 'settled' | 'defaulted' | 'cancelled';
  created_at: string;
}

export async function listCommodityDerivativesAndOHLC(
  client: any,
  commodity: string = 'energy',
  humanId: string = 'H-0044'
): Promise<{
  ok: boolean;
  commodity: string;
  ohlc: OHLCSnapshot[];
  ma7: (number | null)[];
  ma25: (number | null)[];
  orderbook: FuturesContract[];
  userPositions: FuturesContract[];
}> {
  const c = commodity.toLowerCase();

  // 1. Fetch OHLC snapshots
  const ohlcRes = await client.query(
    `SELECT * FROM market_ohlc_snapshots
     WHERE commodity = $1
     ORDER BY game_day ASC
     LIMIT 50`,
    [c]
  );

  const ohlc: OHLCSnapshot[] = ohlcRes.rows;

  // Compute Moving Averages
  const closes = ohlc.map((s) => Number(s.close_price));
  const ma7: (number | null)[] = [];
  const ma25: (number | null)[] = [];

  for (let i = 0; i < closes.length; i++) {
    if (i >= 6) {
      const sum7 = closes.slice(i - 6, i + 1).reduce((a, b) => a + b, 0);
      ma7.push(Math.round((sum7 / 7) * 100) / 100);
    } else {
      ma7.push(null);
    }

    if (i >= 24) {
      const sum25 = closes.slice(i - 24, i + 1).reduce((a, b) => a + b, 0);
      ma25.push(Math.round((sum25 / 25) * 100) / 100);
    } else {
      ma25.push(null);
    }
  }

  // 2. Fetch Open Futures Orderbook for this commodity
  const orderbookRes = await client.query(
    `SELECT f.*, h.id as seller_id
     FROM commodity_futures_contracts f
     LEFT JOIN humans h ON f.seller_human_id = h.id
     WHERE f.commodity = $1 AND f.status = 'open'
     ORDER BY f.strike_price ASC, f.expiry_game_day ASC
     LIMIT 50`,
    [c]
  );

  // 3. Fetch User's positions across all commodities
  const positionsRes = await client.query(
    `SELECT f.*
     FROM commodity_futures_contracts f
     WHERE f.seller_human_id = $1 OR f.buyer_human_id = $1
     ORDER BY f.expiry_game_day ASC, f.created_at DESC
     LIMIT 50`,
    [humanId]
  );

  return {
    ok: true,
    commodity: c,
    ohlc,
    ma7,
    ma25,
    orderbook: orderbookRes.rows,
    userPositions: positionsRes.rows,
  };
}

export async function createFuturesListing(
  client: PostgresRepository,
  params: {
    sellerId: string;
    commodity: string;
    size: number;
    strikePrice: number;
    durationGameMinutes: number;
    correlationId?: string;
  }
): Promise<{ ok: boolean; contractId: string; commodity: string; size: number; strikePrice: number; expiryGameDay: number }> {
  const { sellerId, commodity, size, strikePrice, durationGameMinutes } = params;
  const c = commodity.toLowerCase();

  if (!['energy', 'material', 'compute', 'food'].includes(c)) {
    throw new Error(`Invalid commodity type '${commodity}'.`);
  }
  if (!Number.isFinite(size) || size <= 0) {
    throw new Error('Contract size must be greater than 0.');
  }
  if (!Number.isFinite(strikePrice) || strikePrice <= 0) {
    throw new Error('Strike price must be greater than 0.');
  }
  if (!Number.isInteger(durationGameMinutes) || durationGameMinutes < 1 || durationGameMinutes > 525600) {
    throw new Error('Duration must be between 1 and 525,600 game minutes.');
  }

  return transactional(client, async () => {
  const world = await client.query<{ genesis_at: string | null; simulated_day_offset: number | null }>("SELECT genesis_at, simulated_day_offset FROM world_state WHERE id = 'WORLD'");
  const now = getAuthoritativeGameTime({ genesisAt: world.rows[0]?.genesis_at, simulatedDayOffset: world.rows[0]?.simulated_day_offset });
  const expiryAbsoluteMinute = now.totalGameMinutes + durationGameMinutes;
  const expiryGameDay = Math.floor(expiryAbsoluteMinute / 1440) + 1;
  // Check seller resource balance
  const balRes = await client.query(
    `SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE`,
    [sellerId, c]
  );
  const currentBal = balRes.rows.length > 0 ? Number(balRes.rows[0].amount) : 0;
  if (currentBal < size) {
    throw new Error(`Insufficient ${c.toUpperCase()} balance for collateral. Available: ${currentBal.toFixed(1)}, required: ${size.toFixed(1)}`);
  }

  // Lock collateral
  await client.query(
    `UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3`,
    [size, sellerId, c]
  );

  const contractId = `FUT-${c.toUpperCase()}-${Date.now()}`;
  await client.query(
    `INSERT INTO commodity_futures_contracts (
       id, seller_human_id, buyer_human_id, commodity, contract_size, strike_price, expiry_game_day, collateral_locked, premium_paid, status
     ) VALUES ($1, $2, null, $3, $4, $5, $6, $7, 0, 'open')`,
    [contractId, sellerId, c, size, strikePrice, expiryGameDay, size]
  );

  return {
    ok: true,
    contractId,
    commodity: c,
    size,
    strikePrice,
    expiryGameDay,
  };
  });
}

export async function matchFuturesContract(
  client: PostgresRepository,
  params: {
    buyerId: string;
    contractId: string;
    correlationId?: string;
  }
): Promise<{ ok: boolean; contractId: string; totalPaid: string; status: string }> {
  return transactional(client, async () => {
  const { buyerId, contractId } = params;

  const fRes = await client.query(
    `SELECT * FROM commodity_futures_contracts WHERE id = $1 FOR UPDATE`,
    [contractId]
  );
  if (fRes.rows.length === 0) {
    throw new Error('Futures contract not found.');
  }
  const contract = fRes.rows[0];

  if (contract.status !== 'open') {
    throw new Error(`Cannot match contract. Current status is '${contract.status}'.`);
  }
  if (contract.seller_human_id === buyerId) {
    throw new Error('Cannot buy your own futures contract listing.');
  }

  const totalCost = Number(contract.contract_size) * Number(contract.strike_price);

  // Check buyer Credits balance
  const buyerAcc = await client.query(
    `SELECT ab.balance, ab.account_id
     FROM humans h
     JOIN account_balances ab ON h.account_id = ab.account_id
     WHERE h.id = $1 FOR UPDATE`,
    [buyerId]
  );
  if (buyerAcc.rows.length === 0) {
    throw new Error('Buyer account not found.');
  }
  const buyerCredits = Number(buyerAcc.rows[0].balance);
  if (buyerCredits < totalCost) {
    throw new Error(`Insufficient credits to purchase futures contract. Required: ${totalCost.toFixed(2)} CR, available: ${buyerCredits.toFixed(2)} CR.`);
  }

  // Deduct from buyer
  await client.query(
    `UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2`,
    [totalCost, buyerAcc.rows[0].account_id]
  );

  // Mark contract matched
  await client.query(
    `UPDATE commodity_futures_contracts
     SET buyer_human_id = $1, status = 'matched', premium_paid = $2
     WHERE id = $3`,
    [buyerId, totalCost, contractId]
  );

  return {
    ok: true,
    contractId,
    totalPaid: totalCost.toFixed(2),
    status: 'matched',
  };
  });
}

export async function cancelFuturesListing(
  client: PostgresRepository,
  params: {
    sellerId: string;
    contractId: string;
  }
): Promise<{ ok: boolean; contractId: string; status: string }> {
  return transactional(client, async () => {
  const { sellerId, contractId } = params;

  const fRes = await client.query(
    `SELECT * FROM commodity_futures_contracts WHERE id = $1 FOR UPDATE`,
    [contractId]
  );
  if (fRes.rows.length === 0) {
    throw new Error('Futures contract not found.');
  }
  const contract = fRes.rows[0];

  if (contract.seller_human_id !== sellerId) {
    throw new Error('Only the seller may cancel an open futures listing.');
  }
  if (contract.status !== 'open') {
    throw new Error(`Cannot cancel contract with status '${contract.status}'.`);
  }

  const size = Number(contract.contract_size);
  const c = contract.commodity;

  // Refund collateral
  await client.query(
    `INSERT INTO resource_balances (owner_id, resource, amount)
     VALUES ($1, $2, $3)
     ON CONFLICT (owner_id, resource)
     DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount`,
    [sellerId, c, size]
  );

  await client.query(
    `UPDATE commodity_futures_contracts SET status = 'cancelled' WHERE id = $1`,
    [contractId]
  );

  return {
    ok: true,
    contractId,
    status: 'cancelled',
  };
  });
}

export async function settleExpiringFutures(
  client: PostgresRepository,
  currentDay: number
): Promise<{ settledCount: number }> {
  return transactional(client, async () => {
  const maturingRes = await client.query(
    `SELECT * FROM commodity_futures_contracts
     WHERE status = 'matched' AND expiry_game_day <= $1
     FOR UPDATE`,
    [currentDay]
  );

  let settledCount = 0;
  for (const contract of maturingRes.rows) {
    const size = Number(contract.contract_size);
    const c = contract.commodity;
    const strikeAmount = Number(contract.premium_paid) || (size * Number(contract.strike_price));

    // 1. Deliver commodity to buyer
    if (contract.buyer_human_id) {
      await client.query(
        `INSERT INTO resource_balances (owner_id, resource, amount)
         VALUES ($1, $2, $3)
         ON CONFLICT (owner_id, resource)
         DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount`,
        [contract.buyer_human_id, c, size]
      );
    }

    // 2. Transfer strike payment to seller
    const sellerAcc = await client.query(
      `SELECT ab.account_id FROM humans h JOIN account_balances ab ON h.account_id = ab.account_id WHERE h.id = $1`,
      [contract.seller_human_id]
    );
    if (sellerAcc.rows.length > 0) {
      await client.query(
        `UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2`,
        [strikeAmount, sellerAcc.rows[0].account_id]
      );
    }

    await client.query(
      `UPDATE commodity_futures_contracts SET status = 'settled' WHERE id = $1`,
      [contract.id]
    );

    settledCount++;
  }

  return { settledCount };
  });
}
import type { PostgresRepository } from './repository.ts';

async function transactional<T>(repository: PostgresRepository, work: () => Promise<T>): Promise<T> {
  return repository.transaction(async () => work());
}
