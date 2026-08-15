import test from 'node:test';
import assert from 'node:assert/strict';
import { deliverOutbox, enqueueOutbox } from '../cloudflare/src/outbox-postgres.ts';

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
      if (event) event.claimed = true;
      return { rowCount: event ? 1 : 0, rows: [] };
    }
    if (sql.includes('SET processed_at = CURRENT_TIMESTAMP')) {
      const event = this.events.find((candidate) => candidate.id === params[0]);
      if (event) event.processed = true;
      return { rowCount: event ? 1 : 0, rows: [] };
    }
    if (sql.includes('SET locked_at = NULL')) return { rowCount: 1, rows: [] };
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
  const retry = repository.queries.find(({ sql }) => sql.includes('SET locked_at = NULL'));
  assert.match(retry.params[1], /temporary coordinator outage/);
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
