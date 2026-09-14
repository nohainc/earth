import test from 'node:test';
import assert from 'node:assert/strict';
import { EarthDomainError, errorResponse, mapPostgresError } from '../cloudflare/src/errors.ts';

test('Community name conflicts map from PostgreSQL constraint to a stable 409 error', async () => {
  const mapped = mapPostgresError({ code: '23505', constraint: 'communities_active_normalized_name_uq', detail: 'duplicate key contains founder_house_id' });
  assert.ok(mapped instanceof EarthDomainError);
  assert.equal(mapped.code, 'COMMUNITY_NAME_TAKEN');
  assert.equal(mapped.status, 409);
  assert.equal(mapped.publicMessage, 'A community with this name already exists.');
  assert.equal(mapped.details?.field, 'name');

  const response = errorResponse({ code: '23505', constraint: 'communities_active_normalized_name_uq', detail: 'private database detail' }, 'corr-1');
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), {
    ok: false,
    code: 'COMMUNITY_NAME_TAKEN',
    error: 'A community with this name already exists.',
    correlationId: 'corr-1',
    field: 'name',
  });
});

test('unknown errors become generic internal errors without leaking diagnostics', async () => {
  const response = errorResponse(new Error('SQL text and secrets must not be returned'), 'corr-2', 'Community operation failed.');
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), {
    ok: false,
    code: 'INTERNAL_ERROR',
    error: 'Community operation failed.',
    correlationId: 'corr-2',
  });
});

test('the API error helper is the shared response boundary', async () => {
  const module = await import('../cloudflare/src/errors.ts');
  assert.equal(module.toApiErrorResponse, module.errorResponse);
});
