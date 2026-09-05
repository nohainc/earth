import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listCommodityDerivativesAndOHLC,
  createFuturesListing,
  matchFuturesContract,
  cancelFuturesListing,
  settleExpiringFutures,
} from '../cloudflare/src/derivatives-postgres.ts';

function createMockDb() {
  const ohlc = [
    { id: '1', commodity: 'energy', game_day: 1, open_price: '28.00', high_price: '31.00', low_price: '27.00', close_price: '30.00', volume: '1000' },
    { id: '2', commodity: 'energy', game_day: 2, open_price: '30.00', high_price: '32.00', low_price: '29.00', close_price: '31.00', volume: '1200' },
    { id: '3', commodity: 'energy', game_day: 3, open_price: '31.00', high_price: '33.00', low_price: '30.00', close_price: '32.00', volume: '1500' },
    { id: '4', commodity: 'energy', game_day: 4, open_price: '32.00', high_price: '34.00', low_price: '31.00', close_price: '33.00', volume: '1100' },
    { id: '5', commodity: 'energy', game_day: 5, open_price: '33.00', high_price: '35.00', low_price: '32.00', close_price: '34.00', volume: '1300' },
    { id: '6', commodity: 'energy', game_day: 6, open_price: '34.00', high_price: '36.00', low_price: '33.00', close_price: '35.00', volume: '1400' },
    { id: '7', commodity: 'energy', game_day: 7, open_price: '35.00', high_price: '37.00', low_price: '34.00', close_price: '36.00', volume: '1600' },
  ];

  const contracts = [
    {
      id: 'FUT-ENERGY-101',
      seller_human_id: 'H-0044',
      buyer_human_id: null,
      commodity: 'energy',
      contract_size: '250.00',
      strike_price: '28.50',
      expiry_game_day: 210,
      collateral_locked: '250.00',
      premium_paid: '0.00',
      status: 'open',
      created_at: new Date().toISOString(),
    },
    {
      id: 'FUT-COMPUTE-102',
      seller_human_id: 'H-0012',
      buyer_human_id: 'H-0044',
      commodity: 'compute',
      contract_size: '100.00',
      strike_price: '58.00',
      expiry_game_day: 180,
      collateral_locked: '100.00',
      premium_paid: '5800.00',
      status: 'matched',
      created_at: new Date().toISOString(),
    },
  ];

  const balances = {
    'H-0044': { energy: 500, compute: 200 },
    'H-0012': { energy: 100, compute: 300 },
  };

  const accounts = {
    'H-0044': { account_id: 'ACC-0044', balance: 50000 },
    'H-0012': { account_id: 'ACC-0012', balance: 25000 },
  };

  const repository = {
    async query(sql, params = []) {
      const s = sql.trim().toUpperCase();

      if (s.includes('FROM MARKET_OHLC_SNAPSHOTS')) {
        return { rows: ohlc.filter((x) => x.commodity === params[0]) };
      }

      if (s.includes('FROM COMMODITY_FUTURES_CONTRACTS') && s.includes("STATUS = 'OPEN'")) {
        return { rows: contracts.filter((x) => x.commodity === params[0] && x.status === 'open') };
      }

      if (s.includes('FROM COMMODITY_FUTURES_CONTRACTS') && s.includes('WHERE F.SELLER_HUMAN_ID = $1 OR F.BUYER_HUMAN_ID = $1')) {
        return { rows: contracts.filter((x) => x.seller_human_id === params[0] || x.buyer_human_id === params[0]) };
      }

      if (s.includes('FROM COMMODITY_FUTURES_CONTRACTS WHERE ID = $1')) {
        const found = contracts.find((x) => x.id === params[0]);
        return { rows: found ? [found] : [] };
      }

      if (s.includes('FROM COMMODITY_FUTURES_CONTRACTS') && s.includes("STATUS = 'MATCHED' AND EXPIRY_GAME_DAY <=")) {
        const rows = contracts.filter((x) => x.status === 'matched' && Number(x.expiry_game_day) <= params[0]);
        return { rows };
      }

      if (s.includes('FROM RESOURCE_BALANCES WHERE OWNER_ID = $1 AND RESOURCE = $2')) {
        const b = balances[params[0]]?.[params[1]] || 0;
        return { rows: [{ amount: b }] };
      }

      if (s.includes('UPDATE RESOURCE_BALANCES SET AMOUNT = AMOUNT - $1 WHERE OWNER_ID = $2 AND RESOURCE = $3')) {
        if (balances[params[1]]) balances[params[1]][params[2]] -= params[0];
        return { rows: [] };
      }

      if (s.includes('INSERT INTO COMMODITY_FUTURES_CONTRACTS')) {
        const newC = {
          id: params[0],
          seller_human_id: params[1],
          buyer_human_id: null,
          commodity: params[2],
          contract_size: params[3],
          strike_price: params[4],
          expiry_game_day: params[5],
          collateral_locked: params[6],
          premium_paid: 0,
          status: 'open',
        };
        contracts.push(newC);
        return { rows: [newC] };
      }

      if (s.includes('FROM HUMANS H') && s.includes('JOIN ACCOUNT_BALANCES AB')) {
        const acc = accounts[params[0]];
        return { rows: acc ? [acc] : [] };
      }

      if (s.includes('UPDATE ACCOUNT_BALANCES SET BALANCE = BALANCE - $1 WHERE ACCOUNT_ID = $2')) {
        for (const k of Object.keys(accounts)) {
          if (accounts[k].account_id === params[1]) accounts[k].balance -= params[0];
        }
        return { rows: [] };
      }

      if (s.includes('UPDATE ACCOUNT_BALANCES SET BALANCE = BALANCE + $1 WHERE ACCOUNT_ID = $2')) {
        for (const k of Object.keys(accounts)) {
          if (accounts[k].account_id === params[1]) accounts[k].balance += params[0];
        }
        return { rows: [] };
      }

      if (s.includes('UPDATE COMMODITY_FUTURES_CONTRACTS') && s.includes("STATUS = 'MATCHED'")) {
        const found = contracts.find((x) => x.id === params[2]);
        if (found) {
          found.buyer_human_id = params[0];
          found.status = 'matched';
          found.premium_paid = params[1];
        }
        return { rows: [] };
      }

      if (s.includes('UPDATE COMMODITY_FUTURES_CONTRACTS SET STATUS = $1 WHERE ID = $2') || s.includes('UPDATE COMMODITY_FUTURES_CONTRACTS SET STATUS = \'CANCELLED\' WHERE ID = $1')) {
        const id = params.length === 1 ? params[0] : params[1];
        const found = contracts.find((x) => x.id === id);
        if (found) found.status = params.length === 1 ? 'cancelled' : params[0];
        return { rows: [] };
      }

      if (s.includes('UPDATE COMMODITY_FUTURES_CONTRACTS SET STATUS = \'SETTLED\' WHERE ID = $1')) {
        const found = contracts.find((x) => x.id === params[0]);
        if (found) found.status = 'settled';
        return { rows: [] };
      }

      return { rows: [] };
    },
  };
  repository.transaction = async (work) => work(repository);
  return repository;
}

test('listCommodityDerivativesAndOHLC computes moving averages and returns data', async () => {
  const db = createMockDb();
  const res = await listCommodityDerivativesAndOHLC(db, 'energy', 'H-0044');

  assert.equal(res.ok, true);
  assert.equal(res.commodity, 'energy');
  assert.equal(res.ohlc.length, 7);
  assert.equal(res.ma7.length, 7);
  assert.equal(typeof res.ma7[6], 'number');
  assert.equal(res.orderbook.length, 1);
  assert.equal(res.userPositions.length, 2);
});

test('createFuturesListing locks collateral and creates contract', async () => {
  const db = createMockDb();
  const res = await createFuturesListing(db, {
    sellerId: 'H-0044',
    commodity: 'energy',
    size: 100,
    strikePrice: 29.50,
    durationGameMinutes: 220,
  });

  assert.equal(res.ok, true);
  assert.equal(res.commodity, 'energy');
  assert.equal(res.size, 100);
});

test('matchFuturesContract deducts credits and transitions status to matched', async () => {
  const db = createMockDb();
  const res = await matchFuturesContract(db, {
    buyerId: 'H-0012',
    contractId: 'FUT-ENERGY-101',
  });

  assert.equal(res.ok, true);
  assert.equal(res.status, 'matched');
});

test('cancelFuturesListing and settleExpiringFutures work correctly', async () => {
  const db = createMockDb();
  const cancelRes = await cancelFuturesListing(db, {
    sellerId: 'H-0044',
    contractId: 'FUT-ENERGY-101',
  });
  assert.equal(cancelRes.ok, true);
  assert.equal(cancelRes.status, 'cancelled');

  const settleRes = await settleExpiringFutures(db, 190);
  assert.equal(settleRes.settledCount, 1);
});
