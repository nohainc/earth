import test from 'node:test';
import assert from 'node:assert/strict';
import { parseJsonBody, resolveIdempotencyKey } from '../cloudflare/src/request-validation.ts';

test('resolves Idempotency-Key and rejects conflicting legacy correlation IDs', () => {
  const header = new Request('https://earth.test/api', {
    headers: { 'Idempotency-Key': 'header-command-1' },
  });
  const matching = new Request('https://earth.test/api', {
    headers: { 'Idempotency-Key': 'same-command' },
  });
  const conflicting = new Request('https://earth.test/api', {
    headers: { 'Idempotency-Key': 'header-command-2' },
  });
  assert.equal(resolveIdempotencyKey(header), 'header-command-1');
  assert.equal(resolveIdempotencyKey(matching, 'same-command'), 'same-command');
  assert.equal(resolveIdempotencyKey(conflicting, 'body-command-2'), null);
});

test('parses JSON object bodies', async () => {
  const result = await parseJsonBody(new Request('https://earth.test/api', { method: 'POST', body: JSON.stringify({ amount: 12 }) }));
  assert.equal(result.ok, true);
  assert.deepEqual(result.value, { amount: 12 });
});

test('rejects malformed and non-object JSON bodies with validation responses', async () => {
  const malformed = await parseJsonBody(new Request('https://earth.test/api', { method: 'POST', body: '{' }));
  const array = await parseJsonBody(new Request('https://earth.test/api', { method: 'POST', body: '[]' }));
  assert.equal(malformed.ok, false);
  assert.equal(array.ok, false);
  assert.equal(malformed.response.status, 400);
  assert.equal(array.response.status, 400);
  assert.equal((await malformed.response.clone().json()).code, 'VALIDATION_ERROR');
  assert.equal(typeof (await array.response.clone().json()).correlationId, 'string');
});

test('rejects oversized request bodies before JSON parsing', async () => {
  const result = await parseJsonBody(new Request('https://earth.test/api', { method: 'POST', body: '1234567890' }), 8);
  assert.equal(result.ok, false);
  assert.equal(result.response.status, 413);
  assert.equal((await result.response.json()).code, 'PAYLOAD_TOO_LARGE');
});
