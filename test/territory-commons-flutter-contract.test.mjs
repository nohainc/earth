import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Flutter retires the standalone Territory rights and commons surface', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_real_estate.dart', 'utf8');
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  const command = fs.readFileSync('flutter_client/lib/features/command_center/command_center_screen.dart', 'utf8');
  const sidebar = fs.readFileSync('flutter_client/lib/features/command_center/sidebar.dart', 'utf8');
  assert.doesNotMatch(api, /territoryRights|commonsStatement/);
  assert.doesNotMatch(api, /acquireTerritoryRight|releaseTerritoryRight/);
  assert.doesNotMatch(dashboard, /TerritoryOverviewPanel|territoryCommonsData/);
  assert.doesNotMatch(command, /getHouseResidency|commonsStatement|territoryCommonsData/);
  assert.match(sidebar, /NavigationRegistry/);
});
