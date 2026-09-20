import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { formatCreditUnits } from '../cloudflare/src/money.ts';

const read = (path) => fs.readFileSync(path, 'utf8');

test('atomic CREDIT formatting preserves the 100-units-per-CREDIT contract', () => {
  assert.equal(formatCreditUnits(50_000n), '500.00');
  assert.equal(formatCreditUnits(1n), '0.01');
  assert.equal(formatCreditUnits(9_007_199_254_740_993n), '90071992547409.93');
});

test('research and building cost projections keep CREDIT units as strings', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const buildingResearch = read('cloudflare/src/corporation-building-research-postgres.ts');
  const buildingUi = read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const technologyUi = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.match(technology, /credit_cost_units::TEXT AS research_credit_cost_units/);
  assert.match(technology, /BigInt\(catalogEntry\.research_credit_cost_units\)/);
  assert.match(buildingResearch, /researchCostUnits: costUnits\.toString\(\)/);
  assert.match(buildingUi, /formatCreditUnits\(serverQuote\['researchCostUnits'\]\)/);
  assert.match(technologyUi, /formatCreditUnits/);
  assert.doesNotMatch(technologyUi, /formatWholeNumber\(nextResearchCost/);
});

test('research submission parses decimal CREDIT at the server boundary', () => {
  const index = read('cloudflare/src/index.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  assert.match(index, /createResearchProjectPostgres\(repository, \{ ownerId: viewer\.id, name, correlationId \}\)/);
  assert.doesNotMatch(index, /body\.budget|body\.focus|moneyToCents/);
  assert.doesNotMatch(technology, /input\.budget|input\.focus|moneyToCents/);
  assert.match(index, /Legacy research funding is retired/);
  assert.match(index, /status: 410/);
});

test('research composer has no client-controlled budget or focus', () => {
  const api = read('flutter_client/lib/core/api/earth_api_technology.dart');
  const dialog = read('flutter_client/lib/features/operations/technology_dialogs.dart');
  assert.match(api, /Future<EarthState> startResearch\(String name\)/);
  assert.doesNotMatch(api, /fundResearch|budget|focus|technology\/me\/fund/);
  assert.match(dialog, /quoteResearch\(name\)/);
  assert.match(dialog, /startResearch\(name\)/);
  assert.doesNotMatch(dialog, /TextEditingController|Research parameter focus|Initial budget/);
});

test('Corporation R&D catalog and review quote expose authoritative status and budget', () => {
  const readModel = read('cloudflare/src/read-postgres.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  const typescript = read('cloudflare/src/technology-read-model.ts');
  const dart = read('flutter_client/lib/core/models/technology_models.dart');
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  const dialog = read('flutter_client/lib/features/operations/technology_dialogs.dart');
  assert.match(readModel, /viewerStatus/);
  assert.match(readModel, /availableUnits/);
  assert.match(typescript, /'AVAILABLE' \| 'ACTIVE' \| 'ADOPTED' \| 'LOCKED'/);
  assert.match(dart, /CorporationResearchBudget/);
  assert.match(panel, /CORPORATION RESEARCH BUDGET/);
  assert.match(panel, /PREREQUISITES:/);
  assert.match(panel, /EFFECTS:/);
  assert.match(technology, /budgetBeforeUnits/);
  assert.match(technology, /budgetAfterUnits/);
  assert.match(dialog, /Budget before:/);
  assert.match(dialog, /Budget after:/);
  assert.match(dialog, /blockers/);
});

test('patents and licenses use Corporation technology access while subscriptions and Organization adoption are retired', () => {
  const readModel = read('cloudflare/src/read-postgres.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  const routes = read('cloudflare/src/organizations-routes.ts');
  const registry = read('cloudflare/src/api-registry.ts');
  const docs = read('docs/v5/V5_MASTER_GAMEPLAY_SPEC.md');
  assert.match(readModel, /earth_resolve_corporation_technology_access/);
  assert.match(readModel, /accessSource/);
  assert.match(technology, /patentable/);
  assert.match(routes, /status: 410/);
  assert.match(routes, /Corporation R&D and V5 Governance/);
  assert.match(registry, /legacyOrganizationTechnologyAdoption.*status: 'RETIRED'/);
  assert.match(docs, /Corporation-to-Corporation contracts/);
  assert.match(docs, /Human-level technology adoption and subscription systems are retired/);
});

test('technology UI does not synthesize resource-flow research recommendations', () => {
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.doesNotMatch(panel, /pressuredResource|_recommendationFor|NEXT RESEARCH DIRECTION/);
  assert.doesNotMatch(panel, /resourceFlows\[.*\].*net/);
});

test('technology catalog supports authoritative discovery and completion countdowns', () => {
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  const model = read('flutter_client/lib/core/models/technology_models.dart');
  assert.match(panel, /Search technologies by name, code, domain, or effect/);
  assert.match(panel, /STATUS FILTER/);
  for (const status of ['ACTIVE', 'AVAILABLE', 'ADOPTED', 'LOCKED']) {
    assert.match(panel, new RegExp(`'${status}'`));
  }
  assert.match(panel, /remainingGameDays/);
  assert.match(panel, /completionGameDay/);
  assert.match(panel, /technology catalogue is read-only/);
  assert.match(model, /viewerStatus/);
});

test('research progress is duration-derived and normalized at the API boundary', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const readModel = read('cloudflare/src/read-postgres.ts');
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.match(technology, /normalizeResearchProject/);
  assert.match(technology, /researchDurationGameDays/);
  assert.match(technology, /progressBps/);
  assert.match(technology, /remainingGameDays/);
  assert.match(technology, /completionGameDay/);
  assert.match(technology, /gameDay < completionGameDay/);
  assert.match(readModel, /normalizeResearchProject/);
  assert.doesNotMatch(panel, /research\['progress'\]|tech\['progress'\]|p\['progress'\]/);
  assert.match(panel, /research\?\.progressBps/);
});

test('V5 technology workspace has typed read models on both boundaries', () => {
  const dart = read('flutter_client/lib/core/models/technology_models.dart');
  const typescript = read('cloudflare/src/technology-read-model.ts');
  for (const type of [
    'TechnologyWorkspace',
    'CorporationResearchProject',
    'TechnologyCatalogEntry',
    'TechnologyEffect',
    'BuildingBlueprintResearch',
    'TechnologyFrontierDomain',
  ]) {
    assert.match(dart, new RegExp(`class ${type}`));
    assert.match(typescript, new RegExp(`type ${type}`));
  }
  assert.match(read('flutter_client/lib/core/models/earth_state.dart'), /technologyWorkspace/);
  assert.match(read('cloudflare/src/read-postgres.ts'), /TechnologyWorkspace/);
});

test('building-tier research uses PRIVATE/PUBLIC scope and Corporation Governance authorization', () => {
  const research = read('cloudflare/src/corporation-building-research-postgres.ts');
  const governance = read('cloudflare/src/v5-governance-postgres.ts');
  const governanceTypes = read('cloudflare/src/v5-governance.ts');
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  const api = read('flutter_client/lib/core/api/earth_api_technology.dart');

  assert.match(research, /blueprintScope: blueprintScope\(target\)/);
  assert.match(research, /fundingSource: 'CORPORATION_OPERATIONS'/);
  assert.match(research, /PUBLIC building research requires a V5 Corporation Governance proposal/);
  assert.match(governanceTypes, /'CORPORATION_BUILDING_RESEARCH'/);
  assert.match(governance, /Only PUBLIC blueprints can use Corporation Governance building research/);
  assert.match(governance, /startCorporationBuildingResearchInTransaction/);
  assert.match(api, /actionType': 'CORPORATION_BUILDING_RESEARCH'/);
  assert.match(panel, /PROPOSE PUBLIC R&D · BUILDING TIER/);
  assert.match(panel, /Corporation operations account/);
  assert.doesNotMatch(panel, /personal account/);
  assert.doesNotMatch(panel, /PROPOSE CIVIC RESEARCH/);
});

test('Earth Technology Frontier is exposed as typed world data with governance navigation', () => {
  const frontier = read('cloudflare/src/earth-technology-frontier-postgres.ts');
  const readModel = read('cloudflare/src/read-postgres.ts');
  const dart = read('flutter_client/lib/core/models/technology_models.dart');
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.match(frontier, /next_generation_number/);
  assert.match(frontier, /next_generation_minimum_game_day/);
  assert.match(readModel, /getEarthTechnologyFrontier/);
  assert.match(readModel, /corporationAccessibleGeneration/);
  assert.match(dart, /nextGenerationMinimumGameDay/);
  assert.match(dart, /corporationAccessibleGeneration/);
  assert.match(panel, /EARTH DOMAIN GENERATION/);
  assert.match(panel, /OPEN GOVERNANCE/);
  assert.match(panel, /onNavigate!.call\('governance'\)/);
});

test('progression terminology distinguishes Building Tier, Domain Generation, and Capability', () => {
  const buildings = read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  const technology = read('flutter_client/lib/features/operations/technology_panel.dart');
  const spec = read('docs/v5/V5_MASTER_GAMEPLAY_SPEC.md');
  assert.match(buildings, /Building Tier/);
  assert.match(buildings, /Domain Generation/);
  assert.match(technology, /Building Tier/);
  assert.match(technology, /Domain Generation/);
  assert.match(technology, /Capability/);
  assert.match(spec, /three distinct progression concepts/);
  assert.match(spec, /\*\*Building Tier\*\*/);
  assert.match(spec, /\*\*Domain Generation\*\*/);
  assert.match(spec, /\*\*Capability\*\*/);
});
