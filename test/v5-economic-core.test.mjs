import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const migration118 = fs.readFileSync('db/migrations/118_v5_economic_core_schema.sql', 'utf8');
const migration119 = fs.readFileSync('db/migrations/119_v5_building_catalog_v5_alpha.sql', 'utf8');
const marketEscrow = fs.readFileSync('cloudflare/src/market-escrow.ts', 'utf8');
const buildingSettlement = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');
const v5Building = fs.readFileSync('cloudflare/src/v5-building-postgres.ts', 'utf8');
const starterPackage = fs.readFileSync('cloudflare/src/starter-package.ts', 'utf8');

test('ECON-01 & ECON-02: canonical resources, storage classes, and services', () => {
  // 5 resources
  const resources = ['ENERGY', 'FOOD', 'MATERIAL', 'COMPONENTS', 'COMPUTE'];
  for (const res of resources) {
    assert.match(migration119, new RegExp(`'${res}'`));
  }
  // 2 launch services
  assert.match(migration119, /'CONNECTIVITY'/);
  assert.match(migration119, /'HEALTH'/);
  // 1 capability
  assert.match(migration119, /'RESEARCH'/);

  // 8 technology domains
  for (const domain of ['ENERGY', 'FOOD', 'MATERIAL', 'COMPONENTS', 'COMPUTE', 'CONNECTIVITY', 'HEALTH', 'RESEARCH']) {
    assert.match(migration118, new RegExp(`'TECH-DOMAIN-${domain}'`));
  }
});

test('ECON-03 & ECON-05: 11 V5 building families across Tiers 1 to 4', () => {
  const houseFamilies = [
    'SOLAR_MICROGRID',
    'VERTICAL_FARM',
    'MATERIALS_RECOVERY',
    'PRECISION_FABRICATION',
    'COMPUTE_CLUSTER',
    'DATA_SERVICES_STUDIO',
    'COMMUNITY_CLINIC',
  ];
  const corpFamilies = [
    'EXTRACTION_REFINING_COMPLEX',
    'CIVIC_DATA_NETWORK',
    'PUBLIC_MEDICAL_CENTER',
    'RESEARCH_EDUCATION_CAMPUS',
  ];

  for (const family of [...houseFamilies, ...corpFamilies]) {
    for (let tier = 1; tier <= 4; tier += 1) {
      assert.match(migration119, new RegExp(`'${family}'[\\s\\S]*?${tier},`));
    }
  }

  // Deactivates legacy generic buildings
  for (const obsolete of ['HOUSING-T1', 'DISTRICT-MODULE-T1', 'MATERIAL-FAB-T1', 'ENERGY-PLANT-T1']) {
    assert.match(migration119, new RegExp(obsolete));
  }
});

test('ECON-04: Corporation resource economics and Market participation', () => {
  // Policies permit Corporation INVENTORY and MARKET_ESCROW
  assert.match(migration118, /\('CORPORATION', 'INVENTORY', 'RESOURCE', TRUE\)/);
  assert.match(migration118, /\('CORPORATION', 'MARKET_ESCROW', 'ANY', TRUE\)/);

  // Market escrow supports both HOUSE and CORPORATION
  assert.match(marketEscrow, /owner\?\.owner_type === 'CORPORATION' \? 'TREASURY' : 'WALLET'/);
  assert.match(marketEscrow, /marketOwnerEconomicId/);
});

test('ECON-06: Construction consumes CREDIT and resources atomically', () => {
  assert.match(v5Building, /loadConstructionRequirements/);
  assert.match(v5Building, /construction_credit_units/);
  assert.match(v5Building, /ECON-CONSTRUCTION-SETTLEMENT/);
  assert.match(v5Building, /ECON-RESOURCE-CONSUMPTION/);
  assert.match(v5Building, /v5_construction_resource_input/);
});

test('ECON-08 & ECON-10: Base production chains and public/private services in settlement', () => {
  assert.match(buildingSettlement, /settlePrivateHouse/);
  assert.match(buildingSettlement, /settlePublicBuilding/);
  assert.match(buildingSettlement, /public_infrastructure_operating_input/);
  assert.match(buildingSettlement, /public_infrastructure_operating_output/);
  assert.match(buildingSettlement, /public_infrastructure_operating_expense/);
});

test('ECON-11 & ECON-12 & ECON-13: Scale Engineering & EARTH Technology Frontier', () => {
  assert.match(migration118, /earth_technology_frontier/);
  assert.match(migration118, /corporation_scale_capabilities/);
  assert.match(migration118, /SCALE_COMMERCIAL/);
  assert.match(migration118, /SCALE_INDUSTRIAL/);
  assert.match(migration118, /SCALE_STRATEGIC/);
});

test('ECON-49: Starter package provides sufficient bootstrap resources', () => {
  assert.match(starterPackage, /material:\s*140/);
  assert.match(starterPackage, /components:\s*15/);
  assert.match(starterPackage, /compute:\s*10/);
  assert.match(starterPackage, /energy:\s*20/);
  assert.match(starterPackage, /food:\s*14/);
});
