import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const institutions = read('cloudflare/src/institutions-postgres.ts');
const institutionsRead = read('cloudflare/src/read-postgres.ts');
const economic = read('cloudflare/src/economic-routes.ts');
const finance = read('cloudflare/src/finance-routes.ts');
const corporationUi = read('flutter_client/lib/features/institutions/institutions_panels.dart');
const houseHud = read('flutter_client/lib/features/command_center/top_fixed_hud_panel.dart');

test('House economy exposes only CREDIT and the five player resources', () => {
  assert.match(economic, /assets\.asset_kind = 'CREDIT'/);
  assert.match(economic, /assets\.asset_kind = 'RESOURCE'/);
  assert.match(economic, /a\.account_type = 'WALLET'/);
  assert.match(economic, /a\.account_type = 'INVENTORY'/);
  assert.doesNotMatch(economic, /earth_private_economic_owner_id|asset_scale|a\.balance\b|account_type::INTEGER/);
  for (const asset of ['energy', 'food', 'material', 'components', 'compute']) assert.match(houseHud, new RegExp(`key: '${asset}'`));
});

test('Corporation and EARTH institution payloads expose CREDIT budgets only', () => {
  assert.match(institutions, /account_type = 'TREASURY'/);
  assert.match(institutions, /account_type = 'OPERATIONS'/);
  assert.match(institutions, /account_type = 'RESERVE'/);
  assert.match(institutionsRead, /earth: \{ treasury:/);
  assert.match(finance, /o\.owner_type IN \('EARTH', 'CORPORATION', 'BANK'\)/);
  assert.match(finance, /a\.asset_id = 1/);
  assert.doesNotMatch(finance, /a\.balance::TEXT/);
  for (const label of ['CORPORATE BUDGET', 'OPERATING BUDGET', 'RESERVE']) assert.match(corporationUi, new RegExp(label));
});

test('Corporation UI does not describe a resource balance surface', () => {
  const start = corporationUi.indexOf('class CorporationOverviewPanel');
  const end = corporationUi.indexOf('class CorporationTerritorySection');
  const overview = corporationUi.slice(start, end === -1 ? undefined : end);
  assert.doesNotMatch(overview, /MATERIAL|ENERGY|FOOD|COMPUTE|COMPONENTS/);
});
