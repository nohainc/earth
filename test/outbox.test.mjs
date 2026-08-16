import test from 'node:test';
import assert from 'node:assert/strict';
import { deliverOutbox, enqueueOutbox, getOutboxMetrics } from '../cloudflare/src/outbox-postgres.ts';

class FakeRepository {
  constructor(events) {
    this.events = events;
    this.queries = [];
  }

  async transaction(work) {
    return work(this);
  }

  async query(sql, params = []) {
    this.queries.push({ sql, params });
    if (sql.includes('SELECT id, event_key')) return { rows: this.events.filter((event) => !event.claimed) };
    if (sql.includes('SET locked_at = CURRENT_TIMESTAMP')) {
      const event = this.events.find((candidate) => candidate.id === params[0]);
      if (event) {
        event.claimed = true;
        event.attempts = (event.attempts || 0) + 1;
      }
      return { rowCount: event ? 1 : 0, rows: [] };
    }
    if (sql.includes('SET processed_at = CURRENT_TIMESTAMP') && !sql.includes('DEAD_LETTER')) {
      const event = this.events.find((candidate) => candidate.id === params[0]);
      if (event) event.processed = true;
      return { rowCount: event ? 1 : 0, rows: [] };
    }
    if (sql.includes('SET locked_at = NULL, processed_at = CURRENT_TIMESTAMP')) {
      const event = this.events.find((candidate) => candidate.id === params[0]);
      if (event) {
        event.processed = true;
        event.deadLettered = true;
        event.lastError = params[1];
      }
      return { rowCount: event ? 1 : 0, rows: [] };
    }
    if (sql.includes('SET locked_at = NULL')) return { rowCount: 1, rows: [] };
    if (sql.includes('COUNT(*) FILTER')) {
      const pending = this.events.filter((e) => !e.processed).length;
      const retry = this.events.filter((e) => !e.processed && e.attempts > 0).length;
      const deadLetter = this.events.filter((e) => e.deadLettered).length;
      return {
        rows: [
          {
            pending_count: String(pending),
            retry_count: String(retry),
            stale_locks_count: '0',
            dead_letter_count: String(deadLetter),
            oldest_pending_age: pending > 0 ? '12.5' : null,
          },
        ],
      };
    }
    if (sql.includes('MAX(processed_at)')) {
      return { rows: [{ last_delivery: '2026-08-16T12:00:00Z' }] };
    }
    return { rowCount: 1, rows: [] };
  }
}

const event = () => ({
  id: '00000000-0000-0000-0000-000000000001',
  event_key: 'market-trade:trade-1',
  topic: 'world_activity',
  aggregate_type: 'market_trade',
  aggregate_id: 'trade-1',
  payload: { type: 'world_activity', category: 'market' },
  attempts: 0,
});

test('outbox marks an event processed only after publication succeeds', async () => {
  const repository = new FakeRepository([event()]);
  const published = [];
  const delivered = await deliverOutbox(repository, async (outboxEvent) => published.push(outboxEvent.payload));
  assert.equal(delivered, 1);
  assert.deepEqual(published, [{ type: 'world_activity', category: 'market' }]);
  assert.equal(repository.events[0].processed, true);
});

test('outbox releases a failed event for retry and records the failure', async () => {
  const repository = new FakeRepository([event()]);
  const delivered = await deliverOutbox(repository, async () => { throw new Error('temporary coordinator outage'); });
  assert.equal(delivered, 0);
  assert.equal(repository.events[0].processed, undefined);
  const retry = repository.queries.find(({ sql }) => sql.includes("available_at = CURRENT_TIMESTAMP + INTERVAL '30 seconds'"));
  assert.ok(retry);
  assert.match(retry.params[1], /temporary coordinator outage/);
});

test('outbox dead-letters events exceeding maximum retry attempts', async () => {
  const exhausted = { ...event(), attempts: 4 }; // will increment to 5 on claim
  const repository = new FakeRepository([exhausted]);
  const delivered = await deliverOutbox(repository, async () => { throw new Error('permanent downstream rejection'); }, 50, 5);
  assert.equal(delivered, 0);
  assert.equal(exhausted.deadLettered, true);
  assert.equal(exhausted.processed, true);
  assert.match(exhausted.lastError, /DEAD_LETTER/);
});

test('enqueue uses an idempotent event key', async () => {
  const repository = new FakeRepository([]);
  await enqueueOutbox(repository, {
    eventKey: 'market-trade:trade-2',
    topic: 'world_activity',
    aggregateType: 'market_trade',
    aggregateId: 'trade-2',
    payload: { type: 'world_activity' },
  });
  assert.match(repository.queries[0].sql, /ON CONFLICT \(event_key\) DO NOTHING/);
  assert.equal(repository.queries[0].params[1], 'market-trade:trade-2');
});

test('outbox delivers events in deterministic ordered sequence', async () => {
  const e1 = { ...event(), id: '00000000-0000-0000-0000-000000000001', event_key: 'seq-1', payload: { seq: 1 } };
  const e2 = { ...event(), id: '00000000-0000-0000-0000-000000000002', event_key: 'seq-2', payload: { seq: 2 } };
  const e3 = { ...event(), id: '00000000-0000-0000-0000-000000000003', event_key: 'seq-3', payload: { seq: 3 } };
  const repository = new FakeRepository([e1, e2, e3]);
  const published = [];
  const delivered = await deliverOutbox(repository, async (outboxEvent) => {
    published.push(outboxEvent.payload.seq);
  });
  assert.equal(delivered, 3);
  assert.deepEqual(published, [1, 2, 3]);
  assert.ok(repository.events.every((ev) => ev.processed));
});

test('partial failure in outbox delivery isolates retries without affecting succeeded events', async () => {
  const e1 = { ...event(), id: 'ev-1', event_key: 'key-1', payload: { id: 1 } };
  const e2 = { ...event(), id: 'ev-2', event_key: 'key-2', payload: { id: 2 } };
  const repository = new FakeRepository([e1, e2]);
  const published = [];
  const delivered = await deliverOutbox(repository, async (outboxEvent) => {
    if (outboxEvent.id === 'ev-2') throw new Error('Downstream channel full');
    published.push(outboxEvent.payload.id);
  });
  assert.equal(delivered, 1);
  assert.deepEqual(published, [1]);
  assert.equal(e1.processed, true);
  assert.equal(e2.processed, undefined);
});

test('getOutboxMetrics computes pending, retry, and dead letter counts correctly', async () => {
  const e1 = { ...event(), id: 'ev-1', attempts: 2 };
  const repository = new FakeRepository([e1]);
  const metrics = await getOutboxMetrics(repository);
  assert.equal(metrics.pendingCount, 1);
  assert.equal(metrics.retryCount, 1);
  assert.equal(metrics.deadLetterCount, 0);
  assert.equal(metrics.oldestPendingAgeSeconds, 12.5);
  assert.equal(metrics.lastSuccessfulDeliveryAt, '2026-08-16T12:00:00Z');
});
