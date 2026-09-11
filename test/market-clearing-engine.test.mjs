import test from 'node:test';
import assert from 'node:assert/strict';
import { clearMarketAuction } from '../cloudflare/src/market-clearing-engine.ts';

const order = (id, ownerId, side, quantityUnits, limitPriceUnits, sequenceNo) => ({ id, ownerId, side, quantityUnits: BigInt(quantityUnits), limitPriceUnits: BigInt(limitPriceUnits), sequenceNo: BigInt(sequenceNo) });

test('call auction chooses maximum executable volume and deterministic fills', () => {
  const result = clearMarketAuction({
    previousClearingPriceUnits: 100n,
    buyOrders: [order('b1', 'h1', 'BUY', 5, 110, 1), order('b2', 'h2', 'BUY', 5, 100, 2)],
    sellOrders: [order('s1', 'h3', 'SELL', 6, 90, 3), order('s2', 'h4', 'SELL', 4, 100, 4)],
  });
  assert.equal(result.clearingPriceUnits, 100n);
  assert.deepEqual(result.fills.map((fill) => [fill.buyOrderId, fill.sellOrderId, fill.quantityUnits]), [['b1', 's1', 5n], ['b2', 's1', 1n], ['b2', 's2', 4n]]);
  assert.equal(result.statistics.executableUnits, 10n);
});

test('same-price orders use sequence priority and self-trade cancels the newer order', () => {
  const result = clearMarketAuction({
    previousClearingPriceUnits: 100n,
    buyOrders: [order('b-old', 'same', 'BUY', 5, 100, 1), order('b-new', 'other', 'BUY', 5, 100, 2)],
    sellOrders: [order('s-self', 'same', 'SELL', 5, 100, 3), order('s-other', 'third', 'SELL', 5, 100, 4)],
  });
  assert.deepEqual(result.selfTradeActions.map((action) => action.cancelledOrderId), ['s-self']);
  assert.deepEqual(result.fills.map((fill) => [fill.buyOrderId, fill.sellOrderId, fill.quantityUnits]), [['b-old', 's-other', 5n]]);
  assert.equal(result.statistics.selfTradePreventedUnits, 5n);
});

test('one-sided books and replay produce no fills and identical output', () => {
  const input = { previousClearingPriceUnits: 100n, buyOrders: [order('b', 'h', 'BUY', 10, 90, 1)], sellOrders: [] };
  const first = clearMarketAuction(input);
  const second = clearMarketAuction(input);
  assert.deepEqual(first, second);
  assert.equal(first.fills.length, 0);
});
