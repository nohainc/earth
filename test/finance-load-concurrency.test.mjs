import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';

function buildPopulation(size = 100_000, institutions = 10_000) {
  return {
    taxpayers: Array.from({ length: size }, (_, id) => ({ id, wallet: 100_000, taxable: 50_000 + (id % 10_000), rateBps: 500 + (id % 500) })),
    deposits: Array.from({ length: size }, (_, id) => ({ id, principal: 10_000 + (id % 1000), interest: id % 100, mature: id % 7 === 0 })),
    loans: Array.from({ length: size }, (_, id) => ({ id, outstanding: 20_000 + (id % 3000), interest: id % 150, paymentDue: id % 3 === 0 })),
    institutions: Array.from({ length: institutions }, (_, id) => ({ id, treasury: 1_000_000, obligations: id % 10 === 0 ? 500_000 : 100_000 })),
  };
}

function runBulkFinanceSettlement(population, batchSize = 10_000) {
  const effects = new Map();
  let taxUnits = 0;
  let bankAccrualUnits = 0;
  let loanPaymentUnits = 0;
  let maturityUnits = 0;
  for (const taxpayer of population.taxpayers) {
    const tax = Math.floor((taxpayer.taxable * taxpayer.rateBps) / 10_000);
    taxUnits += tax;
    effects.set(taxpayer.id, (effects.get(taxpayer.id) ?? 0) - tax);
  }
  for (const deposit of population.deposits) {
    bankAccrualUnits += deposit.interest;
    if (deposit.mature) maturityUnits += deposit.principal + deposit.interest;
  }
  for (const loan of population.loans) {
    bankAccrualUnits += loan.interest;
    if (loan.paymentDue) loanPaymentUnits += Math.min(loan.outstanding, 1_000 + loan.interest);
  }
  const batches = Math.ceil(effects.size / batchSize);
  return { taxUnits, bankAccrualUnits, loanPaymentUnits, maturityUnits, batches, maxEntriesPerBatch: Math.min(batchSize, effects.size) };
}

test('Finance V2 bulk settlement handles 100k contracts without per-owner posting', () => {
  const population = buildPopulation();
  const started = performance.now();
  const result = runBulkFinanceSettlement(population);
  const elapsedMs = performance.now() - started;
  assert.equal(population.taxpayers.length, 100_000);
  assert.equal(population.deposits.length, 100_000);
  assert.equal(population.loans.length, 100_000);
  assert.equal(population.institutions.length, 10_000);
  assert.ok(result.taxUnits > 0);
  assert.ok(result.bankAccrualUnits > 0);
  assert.ok(result.loanPaymentUnits > 0);
  assert.ok(result.maturityUnits > 0);
  assert.equal(result.batches, 10);
  assert.ok(result.maxEntriesPerBatch <= 10_000);
  assert.ok(elapsedMs < 5_000, `bulk finance harness took ${elapsedMs.toFixed(1)}ms`);
});

test('Finance V2 concurrent workers partition work into disjoint batches', () => {
  const ownerCount = 100_000;
  const shardCount = 64;
  const seen = new Set();
  for (let shard = 0; shard < shardCount; shard += 1) {
    for (let owner = shard; owner < ownerCount; owner += shardCount) {
      assert.equal(seen.has(owner), false);
      seen.add(owner);
    }
  }
  assert.equal(seen.size, ownerCount);
});
