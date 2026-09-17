import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Flutter exposes Territory rights and commons as a decision-first read surface', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_real_estate.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/institutions/territory_commons_panel.dart', 'utf8');
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  const command = fs.readFileSync('flutter_client/lib/features/command_center/command_center_screen.dart', 'utf8');
  const sidebar = fs.readFileSync('flutter_client/lib/features/command_center/sidebar.dart', 'utf8');
  assert.match(api, /territoryRights/);
  assert.match(api, /commonsStatement/);
  assert.doesNotMatch(api, /acquireTerritoryRight|releaseTerritoryRight/);
  assert.match(panel, /Read-only physical context/);
  assert.doesNotMatch(panel, /ACQUIRE USE RIGHT|RELEASE USE RIGHT|RELOCATE PRIMARY RESIDENCY/);
  assert.match(panel, /server-derived/);
  assert.match(dashboard, /territory-commons/);
  assert.match(command, /getHouseResidency/);
  assert.match(command, /commonsStatement/);
  assert.match(sidebar, /NavigationRegistry/);
});
