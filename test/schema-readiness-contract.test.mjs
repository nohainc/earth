import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { EARTH_SCHEMA_VERSION } from '../cloudflare/src/schema-contract.ts';
import { isExactSchemaCompatible } from '../cloudflare/src/schema-readiness.ts';

test('runtime schema contract is generated from the canonical manifest', async () => {
  const manifest = JSON.parse(await readFile('db/schema-manifest.json', 'utf8'));
  assert.equal(EARTH_SCHEMA_VERSION, manifest.migrationVersion);
});

test('schema compatibility requires the exact migration and complete object set', () => {
  assert.equal(isExactSchemaCompatible(EARTH_SCHEMA_VERSION - 1, [], EARTH_SCHEMA_VERSION), false);
  assert.equal(isExactSchemaCompatible(EARTH_SCHEMA_VERSION, ['table missing'], EARTH_SCHEMA_VERSION), false);
  assert.equal(isExactSchemaCompatible(EARTH_SCHEMA_VERSION, [], EARTH_SCHEMA_VERSION), true);
});

test('health contract exposes separate liveness and readiness routes', async () => {
  const source = await readFile('cloudflare/src/index.ts', 'utf8');
  assert.match(source, /url\.pathname === '\/api\/live'/);
  assert.match(source, /url\.pathname === '\/api\/ready'/);
  assert.match(source, /healthResponse\(request, env, \{ readiness: true \}\)/);
  assert.match(source, /const healthPath =/);
});
