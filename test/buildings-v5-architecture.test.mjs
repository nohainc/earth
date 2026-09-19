import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { buildingPortfolio } from '../cloudflare/src/building-contract.ts';

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');

test('Buildings UI is scoped to House and Corporation/Public V5 assets', async () => {
  const source = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  for (const obsolete of [
    'investmentShares',
    'civicDividends',
    'districtZoning',
    'public_investment',
    "ownershipClass == 'civic'",
    'state.governance',
    'city_id',
  ]) {
    assert.doesNotMatch(source, new RegExp(obsolete.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(source, /owner_type.*CORPORATION/);
  assert.match(source, /ownershipFilter: 'public'/);
  assert.match(source, /settlement_input_units/);
  assert.match(source, /settlement_output_units/);
});

test('canonical portfolio preserves HOUSE/PRIVATE and CORPORATION/PUBLIC ownership', () => {
  const portfolio = buildingPortfolio(
    [{
      id: 'BLD-HOUSE', catalog_id: 'CAT-PRIVATE', building_type: 'WORKSHOP',
      owner_type: 'HOUSE', owner_id: 'HOUSE-1', ownership_scope: 'PRIVATE',
      status: 'ACTIVE', slot_footprint: '7', utilization_bps: 10000,
      settlement_operating_credit_units: '125',
      settlement_input_units: { ENERGY: '20' },
      settlement_output_units: { MATERIAL: '35' },
    }],
    [{
      id: 'BLD-CORP', catalog_id: 'CAT-PUBLIC', building_type: 'GRID',
      owner_type: 'CORPORATION', owner_id: 'CORP-1', ownership_scope: 'PUBLIC',
      status: 'ACTIVE', slot_footprint: '20', utilization_bps: 9000,
    }],
    [],
    { viewer_can_build: true, viewer_can_propose: false, viewer_can_operate: true },
  );

  assert.equal(portfolio.houseAssets[0].ownerType, 'HOUSE');
  assert.equal(portfolio.houseAssets[0].ownershipScope, 'PRIVATE');
  assert.equal(portfolio.corporationPublicAssets[0].ownerType, 'CORPORATION');
  assert.equal(portfolio.corporationPublicAssets[0].ownershipScope, 'PUBLIC');
  assert.equal(portfolio.houseAssets[0].settlement.operatingCreditUnits, '125');
  assert.deepEqual(portfolio.houseAssets[0].settlement.inputUnits, { ENERGY: '20' });
  assert.deepEqual(portfolio.houseAssets[0].settlement.outputUnits, { MATERIAL: '35' });
  assert.equal(portfolio.corporationPermissions.canPropose, false);
});

test('server quote and settlement concepts remain authoritative at the UI boundary', async () => {
  const source = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const formatter = await read('flutter_client/lib/shared/widgets/format_helpers.dart');
  const investment = await read('cloudflare/src/building-investment-postgres.ts');
  const age = await read('cloudflare/src/building-age-postgres.ts');

  assert.match(source, /quoteV5BuildingContract|quoteV5Building/);
  assert.match(source, /AUTHORIZED ACTIONS/);
  assert.match(source, /LATEST SETTLEMENT FLOWS/);
  assert.match(formatter, /BigInt\.tryParse/);
  assert.match(investment, /SCALE_CAPABILITY_REQUIRED/);
  assert.match(investment, /CAPACITY_UNAVAILABLE/);
  assert.match(investment, /progression:/);
  assert.match(age, /paybackStatus/);
  assert.match(age, /AUTHORITATIVE_INCREMENTAL_ESTIMATE/);
  assert.match(age, /UNAVAILABLE_AUTHORITATIVE_MARKET_PRICES_REQUIRED/);
});
