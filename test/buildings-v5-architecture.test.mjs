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
  assert.match(source, /List<BuildingCatalogEntry> catalog/);
  assert.doesNotMatch(source, /List<dynamic> catalog/);
  assert.doesNotMatch(source, /catalog\.whereType<Map>/);
  assert.match(source, /entry\.familyCode/);
  assert.match(source, /entry\.code/);
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

test('building cards use authoritative economic functions instead of legacy lore', async () => {
  const meta = await read('flutter_client/lib/shared/design_system/earth_building_meta.dart');
  const functionSource = await read('flutter_client/lib/shared/design_system/building_function.dart');
  const buildings = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  assert.doesNotMatch(meta, /getEconomicPurpose|UBI|Dividends|Off-World|Prestige|Liquid Credit Profit/);
  assert.match(functionSource, /resourceFlows/);
  assert.match(functionSource, /TRANSFORMER/);
  assert.match(functionSource, /PRODUCER/);
  assert.match(functionSource, /SERVICE/);
  assert.match(buildings, /buildingEconomicFunction\(item\)/);
  assert.doesNotMatch(buildings, /EarthBuildingMeta\.getEconomicPurpose/);
});

test('catalog cards expose clearly labelled BASE economics', async () => {
  const buildings = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  assert.match(buildings, /BASE ECONOMICS/);
  assert.match(buildings, /BASE CONSTRUCTION COST/);
  assert.match(buildings, /BASE CONSTRUCTION RESOURCES/);
  assert.match(buildings, /BASE CONSTRUCTION TIME/);
  assert.match(buildings, /BASE CAPACITY FOOTPRINT/);
  assert.match(buildings, /BASE OPERATING COST/);
  assert.match(buildings, /BASE INPUT \/ DAY/);
  assert.match(buildings, /BASE OUTPUT \/ DAY/);
  assert.match(buildings, /formatCreditUnits\(item\.constructionCreditUnits\)/);
  assert.match(buildings, /formatCreditUnits\(item\.operatingCreditUnits\)/);
  assert.match(buildings, /constructionFlows/);
  assert.match(buildings, /operatingInputs/);
  assert.match(buildings, /operatingOutputs/);
});

test('construction confirmation is quote-owned', async () => {
  const buildings = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const api = await read('flutter_client/lib/core/api/earth_api_real_estate.dart');
  assert.match(buildings, /quoteV5Building\(buildingType\)/);
  assert.match(buildings, /available .*missing/);
  assert.match(buildings, /Marginal capacity-rent impact/);
  assert.match(buildings, /permissions.*canConstruct/);
  assert.match(buildings, /buildingType: quotedBuildingType/);
  assert.match(buildings, /generation: quotedGeneration/);
  assert.doesNotMatch(buildings, /buildingType: buildingType,\s*\n\s*name: buildingName/);
  assert.match(api, /if \(generation != null\) 'generation': generation/);
});

test('V5 visuals and progression are keyed by all eleven families', async () => {
  const meta = await read('flutter_client/lib/shared/design_system/earth_building_meta.dart');
  const buildings = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const contract = await read('cloudflare/src/building-contract.ts');
  const world = await read('cloudflare/src/world-postgres.ts');
  const upgradeQuote = await read('cloudflare/src/building-investment-postgres.ts');
  for (const family of [
    'SOLAR_MICROGRID',
    'VERTICAL_FARM',
    'MATERIALS_RECOVERY',
    'PRECISION_FABRICATION',
    'COMPUTE_CLUSTER',
    'DATA_SERVICES_STUDIO',
    'COMMUNITY_CLINIC',
    'EXTRACTION_REFINING_COMPLEX',
    'CIVIC_DATA_NETWORK',
    'PUBLIC_MEDICAL_CENTER',
    'RESEARCH_EDUCATION_CAMPUS',
  ]) {
    assert.match(meta, new RegExp(`'${family}':`));
  }
  assert.match(meta, /getFamilyAssetPath/);
  assert.match(buildings, /getFamilyAssetPath\(familyCode\)/);
  assert.match(buildings, /_familyKey\(b\) == _familyKey\(item\)/);
  assert.match(buildings, /_familyKey\(entry\) == installedFamilyKey/);
  assert.match(contract, /familyCode: string \| null/);
  assert.match(world, /c\.code AS building_type, c\.family_code/);
  assert.match(upgradeQuote, /resource_flows/);
  assert.doesNotMatch(upgradeQuote, /resource_input_units|resource_output_units/);
});

test('active V5 catalog rows are renderable and complete', async () => {
  const migration = await read('db/migrations/119_v5_building_catalog_v5_alpha.sql');
  const buildings = await read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const families = [
    'SOLAR_MICROGRID',
    'VERTICAL_FARM',
    'MATERIALS_RECOVERY',
    'PRECISION_FABRICATION',
    'COMPUTE_CLUSTER',
    'DATA_SERVICES_STUDIO',
    'COMMUNITY_CLINIC',
    'EXTRACTION_REFINING_COMPLEX',
    'CIVIC_DATA_NETWORK',
    'PUBLIC_MEDICAL_CENTER',
    'RESEARCH_EDUCATION_CAMPUS',
  ];
  const rows = migration.split('\n').filter((line) =>
    /^\s*\('[A-Z0-9-]+',/.test(line) && line.includes("'standard',"));
  const flowSection = migration.slice(migration.indexOf('WITH flows'));
  assert.equal(rows.length, 44, 'V5 catalog must contain 11 families × 4 tiers');
  for (const family of families) {
    const familyRows = rows.filter((line) => line.includes(`'${family}'`));
    assert.equal(familyRows.length, 4, `${family} must have four tiers`);
    assert.deepEqual(
      familyRows.map((line) => Number(line.match(/, 'standard', (\d),/)?.[1])).sort(),
      [1, 2, 3, 4],
      `${family} tiers must be contiguous`,
    );
    for (const row of familyRows) {
      assert.match(row, /, 'standard', \d, '[^']+', '[^']+',/,
        `${family} row must have a nonempty name and description`);
      const catalogId = row.match(/^\s*\('([^']+)'/)?.[1];
      assert.ok(catalogId && flowSection.includes(`('${catalogId}',`),
        `${family} row must have resource-flow data`);
    }
  }
  assert.match(buildings, /resourceFlows/);
  assert.match(buildings, /flowValue\(flow, key\)/);
  assert.match(buildings, /flowSummary\(currentBlueprint/);
  assert.doesNotMatch(buildings, /Tier 1 Blueprint/);
  assert.doesNotMatch(buildings, /\?\? ['"]Blueprint['"]/);
  assert.match(buildings, /formatCreditUnits\(item\.constructionCreditUnits\)/);
  assert.match(buildings, /formatCreditUnits\(item\.operatingCreditUnits\)/);
  assert.match(buildings, /formatCreditUnits\(quote\['creditCostUnits'\]\)/);
  assert.match(buildings, /formatCreditUnits\(opCreditsBase\)/);
});
