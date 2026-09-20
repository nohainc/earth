import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world condition exposure is derived from Earth and Corporation scope', () => {
  const world = fs.readFileSync('cloudflare/src/world-postgres.ts', 'utf8');
  const readModel = fs.readFileSync('cloudflare/src/world-conditions-postgres.ts', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/world/world_conditions_panel.dart', 'utf8');
  assert.match(world, /conditions\.conditions\.filter/);
  assert.match(world, /viewerApplicableConditionCount/);
  assert.match(readModel, /appliesToViewer/);
  assert.match(readModel, /exposureReason/);
  assert.match(world, /authoritativeGameDay/);
  assert.doesNotMatch(world, /territoryId: territory\?\.territory_id/);
  assert.doesNotMatch(world, /territoryName: territory\?\.territory_name/);
  assert.doesNotMatch(panel, /YOUR_TERRITORY|ORGANIZATION_SCOPED|territoryName|membership\?\['territory/);
  assert.match(panel, /AFFECTING YOU/);
  assert.match(panel, /OTHER ACTIVE CONDITIONS/);
  assert.match(panel, /remainingDays/);
  assert.match(panel, /Subsystem:/);
  assert.doesNotMatch(panel, /WORLD TELEMETRY|RESOURCE AVAILABILITY|CAPACITY PRESSURE/);
  assert.match(panel, /effectiveToGameDay/);
  assert.match(panel, /SERVER-RESOLVED EXPOSURE/);
  assert.doesNotMatch(panel, /STALE SNAPSHOT|stale/);
});
