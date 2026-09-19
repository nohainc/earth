import test from 'node:test';
import assert from 'node:assert/strict';
import { buildingPortfolio } from '../cloudflare/src/building-contract.ts';
import fs from 'node:fs';

test('canonical building portfolio separates House and Corporation public assets', () => {
  const portfolio = buildingPortfolio(
    [{
      id: 'BLD-HOUSE', catalog_id: 'CAT-HOUSE', building_type: 'WORKSHOP',
      owner_type: 'HOUSE', owner_id: 'HOUSE-1', ownership_scope: 'PRIVATE',
      status: 'ACTIVE', slot_footprint: '12', utilization_bps: 8000,
      settlement_operating_credit_units: '25',
      settlement_input_units: { ENERGY: '12' },
      settlement_output_units: { MATERIALS: '40' },
      latest_settlement_game_day: 10, latest_settlement_status: 'COMPLETED',
    }],
    [{
      id: 'BLD-CORP', catalog_id: 'CAT-PUBLIC', building_type: 'GRID',
      owner_type: 'CORPORATION', owner_id: 'CORP-1', ownership_scope: 'PUBLIC',
      status: 'ACTIVE', slot_footprint: '40',
    }],
    [{
      id: 'CAT-HOUSE', code: 'WORKSHOP', name: 'Workshop', description: 'Makes components.', category: 'COMMODITY',
      tier: 1, ownership_scope: 'PRIVATE', service_type: null, service_capacity_units: '0',
      construction_credit_units: '10000', construction_minutes: 60,
      slot_footprint: '12', resource_flows: [{
        assetCode: 'MATERIAL', constructionUnits: '120',
        operatingInputUnits: '2', operatingOutputUnits: '0',
      }],
    }],
    {
      viewer_can_build: true,
      viewer_can_propose: false,
      viewer_can_operate: true,
      viewer_can_upgrade: true,
      viewer_can_retrofit: false,
    },
  );

  assert.equal(portfolio.houseAssets[0].ownerId, 'HOUSE-1');
  assert.equal(portfolio.houseAssets[0].settlement.operatingCreditUnits, '25');
  assert.deepEqual(portfolio.houseAssets[0].settlement.inputUnits, { ENERGY: '12' });
  assert.deepEqual(portfolio.houseAssets[0].settlement.outputUnits, { MATERIALS: '40' });
  assert.equal(portfolio.houseAssets[0].operatingPolicy.currentMode, null);
  assert.equal(portfolio.houseAssets[0].operatingPolicy.effectsByMode.CONSERVATIVE.operatingCreditUnits, '21');
  assert.equal(portfolio.corporationPublicAssets[0].permissions.canUpgrade, true);
  assert.equal(portfolio.corporationPermissions.canBuild, true);
  assert.equal(portfolio.corporationPermissions.canPropose, false);
  assert.equal(portfolio.catalog[0].constructionCreditUnits, '10000');
  assert.equal(portfolio.catalog[0].name, 'Workshop');
  assert.equal(portfolio.catalog[0].description, 'Makes components.');
  assert.equal(portfolio.catalog[0].category, 'COMMODITY');
  assert.equal(portfolio.catalog[0].resourceFlows[0].assetCode, 'MATERIAL');
  assert.equal(portfolio.generatedFrom, 'postgres-canonical-building-contract-v5');
});

test('catalog projections expose authoritative display and normalized flow fields', () => {
  const world = fs.readFileSync('cloudflare/src/world-postgres.ts', 'utf8');
  const contract = fs.readFileSync('cloudflare/src/building-contract.ts', 'utf8');
  assert.match(world, /c\.name, c\.description, c\.category/);
  assert.match(world, /'assetCode', a\.code/);
  assert.match(world, /f\.construction_units::TEXT/);
  assert.match(world, /LEFT JOIN economic_assets a ON a\.id = f\.asset_id/);
  for (const field of ['name', 'description', 'category', 'serviceType', 'serviceCapacityUnits', 'BuildingResourceFlow']) {
    assert.match(contract, new RegExp(field));
  }
});
