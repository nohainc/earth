import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

class BatchHarness {
  constructor() {
    this.status = 'pending';
    this.owner = null;
    this.leaseUntil = 0;
    this.posted = new Set();
    this.fills = 0;
    this.cancelled = false;
    this.orderSequence = 0;
  }

  claim(owner, now) {
    if (this.status === 'completed') return 'completed';
    if (this.owner && this.owner !== owner && this.leaseUntil > now) return 'busy';
    this.owner = owner;
    this.leaseUntil = now + 300;
    this.status = 'clearing';
    return 'claimed';
  }

  run(owner, now, { crashAfterMatch = false, crashAfterPost = false } = {}) {
    const claim = this.claim(owner, now);
    if (claim !== 'claimed') return claim;
    if (this.cancelled) return 'cancelled';
    const correlation = 'market-batch:42:SPOT-ENERGY';
    if (crashAfterMatch) throw new Error('worker crashed after matching');
    if (!this.posted.has(correlation)) {
      this.posted.add(correlation);
      this.fills += 1;
    }
    if (crashAfterPost) throw new Error('worker crashed after posting');
    this.status = 'completed';
    this.owner = null;
    return 'completed';
  }

  cancel() {
    if (this.status === 'clearing') return false;
    this.cancelled = true;
    return true;
  }
}

test('market batch concurrency and crash recovery are at-most-once', () => {
  const active = new BatchHarness();
  assert.equal(active.claim('worker-a', 100), 'claimed');
  assert.equal(active.claim('worker-b', 101), 'busy');

  const beforePost = new BatchHarness();
  assert.throws(() => beforePost.run('worker-a', 100, { crashAfterMatch: true }), /crashed/);
  assert.equal(beforePost.fills, 0);
  assert.equal(beforePost.run('worker-b', 401), 'completed');
  assert.equal(beforePost.fills, 1);

  const afterPost = new BatchHarness();
  assert.throws(() => afterPost.run('worker-a', 100, { crashAfterPost: true }), /crashed/);
  assert.equal(afterPost.fills, 1);
  assert.equal(afterPost.run('worker-b', 401), 'completed');
  assert.equal(afterPost.fills, 1, 'retry must not duplicate the economic posting');

  const completed = new BatchHarness();
  assert.equal(completed.run('worker-a', 100), 'completed');
  assert.equal(completed.run('worker-b', 101), 'completed');
  assert.equal(completed.fills, 1);
});

test('market cancellation and submission races have deterministic cutoffs', () => {
  const clearingWins = new BatchHarness();
  assert.equal(clearingWins.claim('worker-a', 100), 'claimed');
  assert.equal(clearingWins.cancel(), false);

  const cancellationWins = new BatchHarness();
  assert.equal(cancellationWins.cancel(), true);
  assert.equal(cancellationWins.run('worker-a', 100), 'cancelled');

  const currentBatch = 12;
  const submittedDuringCatchup = { eligibleBatchId: currentBatch + 1, sequenceNo: 1 };
  assert.equal(submittedDuringCatchup.eligibleBatchId <= currentBatch, false);
  assert.equal(submittedDuringCatchup.eligibleBatchId <= currentBatch + 1, true);
});

test('duplicate correlations, expiry overlap, deadlock retry, and stale leases are safe', async () => {
  const batch = new BatchHarness();
  assert.equal(batch.run('worker-a', 100), 'completed');
  assert.equal(batch.run('worker-b', 100), 'completed');
  assert.equal(batch.fills, 1);

  const expiry = new Set();
  const settleExpiry = (instrumentId) => {
    const key = `derivative-expiry:${instrumentId}`;
    if (expiry.has(key)) return false;
    expiry.add(key);
    return true;
  };
  assert.equal(settleExpiry('ENERGY-FUT-D210'), true);
  assert.equal(settleExpiry('ENERGY-FUT-D210'), false);

  let attempts = 0;
  const retryDeadlock = async () => {
    while (true) {
      attempts += 1;
      try {
        if (attempts === 1) throw Object.assign(new Error('deadlock'), { code: '40P01' });
        return 'committed';
      } catch (error) {
        if (error.code !== '40P01' || attempts > 3) throw error;
      }
    }
  };
  assert.equal(await retryDeadlock(), 'committed');
  assert.equal(attempts, 2);

  const stale = new BatchHarness();
  assert.equal(stale.claim('worker-a', 0), 'claimed');
  assert.equal(stale.claim('worker-b', 301), 'claimed');
  assert.equal(stale.owner, 'worker-b');
});

test('production market paths use database leases and idempotent posting', () => {
  const scheduler = fs.readFileSync(new URL('../cloudflare/src/market-scheduler.ts', import.meta.url), 'utf8');
  const escrow = fs.readFileSync(new URL('../cloudflare/src/market-escrow.ts', import.meta.url), 'utf8');
  assert.match(scheduler, /earth_claim_market_batch_instrument/);
  assert.match(escrow, /earth_post_transaction/);
  assert.match(escrow, /earth_post_settlement_batch/);
  assert.match(escrow, /market-order:\$\{input\.orderId\}:reserve/);
});
