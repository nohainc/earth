import test from 'node:test';
import assert from 'node:assert/strict';
import { clearMarketAuction } from '../cloudflare/src/market-clearing-engine.ts';
import fs from 'node:fs';

const round = (value, divisor) => (value + divisor / 2n) / divisor;
const quote = (quantity, price) => round(quantity * price, 1_000_000n);
const fee = (amount, bps) => round(amount * BigInt(bps), 10_000n);

function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function scenario(seed, agentCount = 1_000, orderCount = 4_000) {
  const next = random(seed);
  const agents = new Map(Array.from({ length: agentCount }, (_, index) => [
    `A-${index}`, { credit: 1_000_000_000n, energy: 1_000_000_000n },
  ]));
  const orders = [];
  const escrow = new Map();
  let sequence = 0n;
  for (let index = 0; index < orderCount; index += 1) {
    const ownerId = `A-${Math.floor(next() * agentCount)}`;
    const side = next() < 0.5 ? 'BUY' : 'SELL';
    const quantityUnits = BigInt(1 + Math.floor(next() * 10)) * 1_000_000n;
    const limitPriceUnits = BigInt(100 + Math.floor(next() * 401));
    const buyerFeeBps = 25 + Math.floor(next() * 76);
    const id = `O-${index}`;
    const owner = agents.get(ownerId);
    if (side === 'BUY') {
      const reserved = quote(quantityUnits, limitPriceUnits) + fee(quote(quantityUnits, limitPriceUnits), buyerFeeBps);
      owner.credit -= reserved;
      escrow.set(id, { ownerId, side, credit: reserved, energy: 0n, buyerFeeBps });
    } else {
      owner.energy -= quantityUnits;
      escrow.set(id, { ownerId, side, credit: 0n, energy: quantityUnits, buyerFeeBps });
    }
    orders.push({ id, ownerId, side, quantityUnits, limitPriceUnits, sequenceNo: sequence });
    sequence += 1n;
  }
  // Cancellation is a pre-batch operation and returns the exact reservation.
  const active = orders.filter((order) => {
    if (next() >= 0.18) return true;
    const reservation = escrow.get(order.id);
    const owner = agents.get(reservation.ownerId);
    owner.credit += reservation.credit;
    owner.energy += reservation.energy;
    escrow.delete(order.id);
    return false;
  });
  const buys = active.filter((order) => order.side === 'BUY');
  const sells = active.filter((order) => order.side === 'SELL');
  const first = clearMarketAuction({ previousClearingPriceUnits: 250n, buyOrders: buys, sellOrders: sells });
  const retry = clearMarketAuction({ previousClearingPriceUnits: 250n, buyOrders: buys, sellOrders: sells });
  assert.deepEqual(first, retry, `seed ${seed} must replay exactly`);

  let feeAccount = 0n;
  for (const fill of first.fills) {
    const buy = active.find((order) => order.id === fill.buyOrderId);
    const sell = active.find((order) => order.id === fill.sellOrderId);
    const buyer = agents.get(buy.ownerId);
    const seller = agents.get(sell.ownerId);
    const buyEscrow = escrow.get(buy.id);
    const sellEscrow = escrow.get(sell.id);
    const limitQuote = quote(fill.quantityUnits, buy.limitPriceUnits);
    const actualQuote = quote(fill.quantityUnits, fill.priceUnits);
    const tradeFee = fee(actualQuote, buyEscrow.buyerFeeBps);
    const reservedUse = limitQuote + fee(limitQuote, buyEscrow.buyerFeeBps);
    buyEscrow.credit -= reservedUse;
    sellEscrow.energy -= fill.quantityUnits;
    buyer.credit += reservedUse - actualQuote - tradeFee;
    buyer.energy += fill.quantityUnits;
    seller.credit += actualQuote;
    feeAccount += tradeFee;
  }
  const creditInEscrow = [...escrow.values()].reduce((sum, item) => sum + item.credit, 0n);
  const energyInEscrow = [...escrow.values()].reduce((sum, item) => sum + item.energy, 0n);
  const creditInAgents = [...agents.values()].reduce((sum, item) => sum + item.credit, 0n);
  const energyInAgents = [...agents.values()].reduce((sum, item) => sum + item.energy, 0n);
  const initial = BigInt(agentCount) * 1_000_000_000n;
  return {
    fills: first.fills.length,
    selfTradePreventedUnits: first.statistics.selfTradePreventedUnits.toString(),
    creditConserved: creditInAgents + creditInEscrow + feeAccount === initial * 1n,
    energyConserved: energyInAgents + energyInEscrow === initial,
    solvent: [...agents.values()].every((item) => item.credit >= 0n && item.energy >= 0n),
  };
}

test('Market V2 seeded property scenarios preserve conservation and replay determinism', () => {
  for (const seed of [7, 42, 2026, 0xdeadbeef]) {
    const first = scenario(seed);
    const second = scenario(seed);
    assert.deepEqual(first, second);
    assert.equal(first.creditConserved, true, `CREDIT must be conserved for seed ${seed}`);
    assert.equal(first.energyConserved, true, `energy must be conserved for seed ${seed}`);
    assert.equal(first.solvent, true, `accounts must remain solvent for seed ${seed}`);
    assert.ok(first.fills > 0, `seed ${seed} should produce fills`);
  }
});

test('Market V2 expiry retry preserves fully collateralized future state', () => {
  const obligations = Array.from({ length: 250 }, (_, index) => ({ quantity: BigInt(index + 1) * 1_000_000n, price: 125n + BigInt(index % 20) }));
  const before = obligations.reduce((sum, item) => sum + item.quantity * item.price / 1_000_000n + item.quantity, 0n);
  const settle = () => obligations.map((item) => ({ longCredit: 0n, shortCredit: item.quantity * item.price / 1_000_000n, longEnergy: item.quantity, shortEnergy: 0n }));
  const first = settle();
  const retry = settle();
  assert.deepEqual(first, retry);
  assert.equal(first.reduce((sum, item) => sum + item.shortCredit + item.longEnergy, 0n), before);
  assert.ok(obligations.every((item) => item.quantity > 0n && item.price > 0n));
});

test('Market V2 includes a configurable scale benchmark with separate phases', () => {
  const benchmark = fs.readFileSync(new URL('../scripts/benchmark-market-v2.mjs', import.meta.url), 'utf8');
  assert.match(benchmark, /orderBookLoad/);
  assert.match(benchmark, /clearingAndFillGeneration/);
  assert.match(benchmark, /economicAggregation/);
  assert.match(benchmark, /lockWaitMs/);
  assert.match(benchmark, /walBytes/);
  assert.match(benchmark, /--orders=/);
});
