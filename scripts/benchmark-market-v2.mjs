import { performance } from 'node:perf_hooks';
import { clearMarketAuction } from '../cloudflare/src/market-clearing-engine.ts';

const DEFAULT_SIZES = [1_000, 10_000];
const requested = process.argv.slice(2).filter((arg) => arg.startsWith('--orders='))[0]?.split('=')[1];
const sizes = requested ? requested.split(',').map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0) : DEFAULT_SIZES;

function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function buildBook(orderCount, seed = 2026) {
  const next = seededRandom(seed);
  const buys = [];
  const sells = [];
  for (let index = 0; index < orderCount; index += 1) {
    const order = {
      id: `O-${index}`,
      ownerId: `A-${Math.floor(next() * Math.max(100, Math.floor(orderCount / 4)))}`,
      quantityUnits: BigInt(1 + Math.floor(next() * 10)) * 1_000_000n,
      filledUnits: 0n,
      limitPriceUnits: BigInt(100 + Math.floor(next() * 900)),
      sequenceNo: BigInt(index),
    };
    (next() < 0.5 ? buys : sells).push({ ...order, side: next() < 0.5 ? 'BUY' : 'SELL' });
  }
  // Keep each side's type aligned with its collection after generation.
  return { buys: buys.map((order) => ({ ...order, side: 'BUY' })), sells: sells.map((order) => ({ ...order, side: 'SELL' })) };
}

function aggregateFills(result) {
  const totals = new Map();
  for (const fill of result.fills) {
    const key = fill.buyOrderId;
    totals.set(key, (totals.get(key) ?? 0n) + fill.quantityUnits);
  }
  return totals.size;
}

function benchmark(orderCount) {
  const memoryBefore = process.memoryUsage().heapUsed;
  const loadStart = performance.now();
  const book = buildBook(orderCount);
  const loadMs = performance.now() - loadStart;
  const clearStart = performance.now();
  const result = clearMarketAuction({ previousClearingPriceUnits: 500n, buyOrders: book.buys, sellOrders: book.sells });
  const clearingMs = performance.now() - clearStart;
  const aggregateStart = performance.now();
  const aggregatedAccounts = aggregateFills(result);
  const aggregationMs = performance.now() - aggregateStart;
  return {
    orderCount,
    buyOrders: book.buys.length,
    sellOrders: book.sells.length,
    fills: result.fills.length,
    executableUnits: result.statistics.executableUnits.toString(),
    selfTradePreventedUnits: result.statistics.selfTradePreventedUnits.toString(),
    timingsMs: { orderBookLoad: Number(loadMs.toFixed(3)), clearingAndFillGeneration: Number(clearingMs.toFixed(3)), economicAggregation: Number(aggregationMs.toFixed(3)) },
    aggregatedAccounts,
    memoryDeltaMiB: Number(((process.memoryUsage().heapUsed - memoryBefore) / 1024 / 1024).toFixed(2)),
    databaseMetrics: { lockWaitMs: null, walBytes: null, queryCount: null, postingMs: null, orderUpdateMs: null, fillInsertionMs: null, batchCompletionMs: null },
  };
}

console.log(JSON.stringify({ benchmark: 'market-v2-pure-engine', generatedAt: new Date().toISOString(), sizes: sizes.map(benchmark), note: 'Database metrics require a live PostgreSQL benchmark run.' }, null, 2));
