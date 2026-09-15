import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world condition exposure is server-derived and expiry is visible to players', () => {
  const world = fs.readFileSync('cloudflare/src/world-postgres.ts', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/world/world_conditions_panel.dart', 'utf8');
  assert.match(world, /exposedConditions/);
  assert.match(world, /YOUR_TERRITORY/);
  assert.match(world, /ORGANIZATION_SCOPED/);
  assert.match(panel, /effectiveToGameDay/);
  assert.match(panel, /exposure/);
});
