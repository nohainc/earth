import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Life & Services panel consumes canonical world service assessments', () => {
  const world = fs.readFileSync('cloudflare/src/world-postgres.ts', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/command_center/service_risk_panel.dart', 'utf8');
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  assert.match(world, /serviceNeeds: needs/);
  assert.match(panel, /state\.json\['serviceNeeds'\]/);
  assert.match(panel, /shortfall_units/);
  assert.match(panel, /CRITICAL/);
  assert.match(dashboard, /ServiceRiskPanel\(state: state\)/);
});
