import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const houseProfile = read('cloudflare/src/house-profile.ts');
const housePostgres = read('cloudflare/src/house-postgres.ts');
const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
const houseUi = read('flutter_client/lib/features/house/house_tree_dialog.dart');

test('House profile exposes the persistent V5 House principal', () => {
  for (const field of [
    'identity',
    'currentHuman',
    'succession',
    'successionPolicy',
    'successionQuote',
    'lineage',
    'history',
    'settlementProfile',
    'economics',
  ]) assert.match(houseProfile, new RegExp(field));

  assert.match(housePostgres, /FROM houses WHERE id = \$1/);
  assert.match(housePostgres, /current_human_id/);
  assert.match(housePostgres, /dynasty_legacy::TEXT/);
  assert.doesNotMatch(housePostgres, /founder_human_id|house_lineage_records|legacy_points/);
});

test('House profile reads Corporation affiliation and V5 capacity facts', () => {
  assert.match(housePostgres, /FROM house_affiliations ha/);
  assert.match(housePostgres, /JOIN institutions i ON i\.id = ha\.corporation_id/);
  assert.match(housePostgres, /FROM v5_house_settlement_profiles/);
  assert.match(houseProfile, /residentialCapacityUnits/);
  assert.match(houseProfile, /productiveCapacityUnits/);
  assert.match(houseProfile, /activeBuildingCount/);
});

test('House succession publishes successor and authoritative cost rules', () => {
  assert.match(housePostgres, /FROM house_succession_plans/);
  assert.match(housePostgres, /EARTH\.SUCCESSION\.COST_UNITS/);
  assert.match(housePostgres, /EARTH\.SUCCESSION\.COST_BPS/);
  assert.match(housePostgres, /EARTH\.SUCCESSION\.TRANSITION_DAYS/);
  assert.match(housePostgres, /estimatedCostUnits/);
  assert.match(lifecycle, /SUCCESSION_COST/);
  assert.match(lifecycle, /postSettlementTransaction/);
  assert.match(lifecycle, /successionCostRuleVersion/);
});

test('House succession rules use the authoritative clock after mutable world time was removed', () => {
  assert.match(housePostgres, /FROM earth_get_current_game_time\(\)/);
  assert.doesNotMatch(housePostgres, /MAX\(game_day\).*FROM world_state/);
});

test('House lineage is reconstructed from Humans and succession events', () => {
  assert.match(housePostgres, /FROM humans WHERE house_id = \$1/);
  assert.match(housePostgres, /FROM succession_events WHERE house_id = \$1/);
  for (const field of [
    'generation',
    'birthGameDay',
    'deathGameDay',
    'standing',
    'finalLegacy',
    'relationship',
    'relatedHumanId',
    'effectiveGameDay',
  ]) assert.match(houseProfile, new RegExp(field));
  assert.doesNotMatch(housePostgres, /house_lineage_records|dynasty_lineage_records/);
});

test('House history uses authoritative game events and stays read-only', () => {
  assert.match(housePostgres, /FROM game_events/);
  assert.match(housePostgres, /actor_house_id = \$1/);
  assert.match(housePostgres, /ORDER BY game_day DESC/);
  assert.match(houseProfile, /history/);
  assert.match(houseUi, /HOUSE HISTORY/);
  assert.match(houseUi, /authoritative game event journal/);
  assert.doesNotMatch(houseUi, /unlockHousePerk|equipHouseHeirloom|forgeHouseHeirloom/);
});

test('Human death changes representation without moving House-owned assets', () => {
  const mortality = lifecycle.slice(
    lifecycle.indexOf('export async function processHouseMortality'),
    lifecycle.indexOf('export async function activatePendingHouseSuccessors'),
  );
  assert.match(mortality, /UPDATE humans SET status = 'DECEASED'/);
  assert.match(mortality, /INSERT INTO succession_events/);
  assert.match(lifecycle, /UPDATE houses SET current_human_id/);
  assert.match(mortality, /house_affiliations/);
  assert.doesNotMatch(mortality, /UPDATE buildings SET owner_economic_id/);
  assert.doesNotMatch(mortality, /DELETE FROM (economic_accounts|owner_registry|buildings)/);
});

test('House UI uses theme-aware light/dark colors', () => {
  assert.match(houseUi, /context\.inkColor/);
  assert.match(houseUi, /context\.mutedColor/);
  assert.doesNotMatch(houseUi, /Colors\.white/);
});
