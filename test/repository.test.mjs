import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository, isRetryablePostgresError } from '../cloudflare/src/repository.ts';

class FakeClient {
  constructor() { this.calls = []; }

  async query(sql) {
    this.calls.push(sql);
    return { rows: [], rowCount: 0 };
  }
}

test('classifies PostgreSQL serialization and deadlock errors as retryable', () => {
  assert.equal(isRetryablePostgresError({ code: '40001' }), true);
  assert.equal(isRetryablePostgresError({ code: '40P01' }), true);
  assert.equal(isRetryablePostgresError({ code: '23505' }), false);
});

test('retries a transient transaction failure and commits the successful attempt', async () => {
  const client = new FakeClient();
  const repository = new PostgresRepository(client);
  let attempts = 0;

  const result = await repository.transaction(async () => {
    attempts += 1;
    if (attempts === 1) throw Object.assign(new Error('serialization failure'), { code: '40001' });
    return 'committed';
  });

  assert.equal(result, 'committed');
  assert.equal(attempts, 2);
  assert.deepEqual(client.calls, ['BEGIN', 'ROLLBACK', 'BEGIN', 'COMMIT']);
});

test('does not retry non-transient failures', async () => {
  const client = new FakeClient();
  const repository = new PostgresRepository(client);
  let attempts = 0;

  await assert.rejects(
    () => repository.transaction(async () => {
      attempts += 1;
      throw Object.assign(new Error('constraint violation'), { code: '23514' });
    }),
    /constraint violation/,
  );

  assert.equal(attempts, 1);
  assert.deepEqual(client.calls, ['BEGIN', 'ROLLBACK']);
});

test('stops after the bounded retry budget', async () => {
  const client = new FakeClient();
  const repository = new PostgresRepository(client);
  let attempts = 0;

  await assert.rejects(
    () => repository.transaction(async () => {
      attempts += 1;
      throw Object.assign(new Error('deadlock'), { code: '40P01' });
    }),
    /deadlock/,
  );

  assert.equal(attempts, 3);
  assert.deepEqual(client.calls, ['BEGIN', 'ROLLBACK', 'BEGIN', 'ROLLBACK', 'BEGIN', 'ROLLBACK']);
});
