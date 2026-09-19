import test from 'node:test';
import assert from 'node:assert/strict';
import { buildingPortfolio } from '../cloudflare/src/building-contract.ts';

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
      id: 'CAT-HOUSE', code: 'WORKSHOP', tier: 1, ownership_scope: 'PRIVATE',
      construction_credit_units: '10000', construction_minutes: 60,
      slot_footprint: '12', resource_flows: [],
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
  assert.equal(portfolio.generatedFrom, 'postgres-canonical-building-contract-v5');
});
