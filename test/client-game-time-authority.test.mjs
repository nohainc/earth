import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('commons dividend declarations use authoritative mutation time only', () => {
  const service = read('cloudflare/src/commons-dividends-postgres.ts');
  const route = read('cloudflare/src/real-estate-routes.ts');

  assert.match(service, /input: \{ humanId: string; territoryId: string; correlationId: string \}/);
  assert.match(service, /const day = clock\.gameDay/);
  assert.doesNotMatch(service, /input\.gameDay/);
  assert.doesNotMatch(route, /parseJsonBody<\{ gameDay\?\:/);
  assert.doesNotMatch(route, /declareCommonsDividend\([^\n]*gameDay/);
});
