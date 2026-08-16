import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

test('API Contract Specification and Schema Validation', async () => {
  const contractPath = resolve('docs/API_SPECIFICATION.json');
  const contractRaw = await readFile(contractPath, 'utf8');
  const contract = JSON.parse(contractRaw);

  assert.equal(contract.openapi, '3.1.0');
  assert.equal(contract.info.version, '2026-08');
  assert.equal(contract.servers[0].url, 'https://earthuc.com');

  // Verify paths
  const requiredPaths = ['/api/health', '/api/world', '/api/market/orders', '/api/governance/proposals/{id}/vote', '/api/history', '/api/events'];
  for (const path of requiredPaths) {
    assert.ok(contract.paths[path], `Contract must document path ${path}`);
  }

  // Verify Error envelope schema
  const errorEnvelope = contract.components.schemas.ErrorEnvelope;
  assert.ok(errorEnvelope);
  const expectedCodes = [
    'VALIDATION_ERROR',
    'AUTHENTICATION_REQUIRED',
    'FORBIDDEN',
    'NOT_FOUND',
    'CONFLICT',
    'RATE_LIMITED',
    'INTERNAL_ERROR',
    'SERVICE_UNAVAILABLE',
  ];
  assert.deepEqual(errorEnvelope.properties.code.enum.sort(), expectedCodes.sort());
});
