import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('V5 research uses the database catalog and fixed catalog pricing', () => {
  const baseline = read('db/migrations/001_baseline.sql');
  const duration = read('db/migrations/087_v5_technology_duration.sql');
  const technology = read('cloudflare/src/technology-postgres.ts');
  assert.match(baseline, /CREATE TABLE technology_catalog/);
  assert.match(baseline, /credit_cost_units BIGINT/);
  assert.match(duration, /research_duration_game_days BIGINT/);
  assert.match(technology, /FROM technology_catalog/);
  assert.match(technology, /BigInt\(catalogEntry\.research_credit_cost_units\)/);
  assert.doesNotMatch(technology, /input\.budget|input\.focus|moneyToCents/);
  assert.doesNotMatch(technology, /fundResearchProject/);
});

test('research funding is Corporation budget authority, not personal cash or overpayment', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const building = read('cloudflare/src/corporation-building-research-postgres.ts');
  for (const source of [technology, building]) {
    assert.match(source, /institution_budget_lines/);
    assert.match(source, /authorized_units-l\.committed_units-l\.spent_units/);
    assert.match(source, /institution_budget_commitments/);
    assert.match(source, /funding_transaction_id/);
    assert.doesNotMatch(source, /personal account|account_balances|input\.budget/);
  }
  assert.match(technology, /budgetBeforeUnits/);
  assert.match(technology, /budgetAfterUnits/);
  assert.match(technology, /INSUFFICIENT_RESEARCH_BUDGET/);
});

test('research progress is duration-derived and normalized at the API boundary', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const readModel = read('cloudflare/src/read-postgres.ts');
  const types = read('cloudflare/src/technology-read-model.ts');
  for (const field of ['progressBps', 'remainingGameDays', 'completionGameDay']) {
    assert.match(technology, new RegExp(field));
    assert.match(types, new RegExp(field));
  }
  assert.match(readModel, /normalizeResearchProject/);
  assert.match(technology, /completionGameDay = storedCompletion > 0/);
  assert.match(technology, /gameDay < completionGameDay/);
});

test('exact CREDIT units remain strings through research and quote paths', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const readModel = read('cloudflare/src/read-postgres.ts');
  const dart = read('flutter_client/lib/core/models/technology_models.dart');
  const ui = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.match(technology, /credit_cost_units::TEXT/);
  assert.match(technology, /researchCostUnits: entry\.research_credit_cost_units/);
  assert.match(technology, /budgetBeforeUnits: budgetBefore\?\.toString/);
  assert.match(readModel, /authorizedUnits/);
  assert.match(readModel, /availableUnits/);
  assert.match(dart, /final String researchCostUnits/);
  assert.match(ui, /formatCreditUnits\(item\.researchCostUnits\)/);
});

test('Building Tier research keeps PRIVATE and PUBLIC scopes distinct', () => {
  const building = read('cloudflare/src/corporation-building-research-postgres.ts');
  const governance = read('cloudflare/src/v5-governance.ts');
  const ui = read('flutter_client/lib/features/operations/buildings_hub_screen.dart');
  assert.match(building, /blueprintScope/);
  assert.match(building, /PRIVATE/);
  assert.match(building, /PUBLIC/);
  assert.match(building, /PUBLIC building research requires a V5 Corporation Governance proposal/);
  assert.match(governance, /CORPORATION_BUILDING_RESEARCH/);
  assert.doesNotMatch(ui, /personal account|PROPOSE CIVIC RESEARCH|CITY-VOTE/);
});

test('public blueprint research is governance-authorized and private research is Corporation-funded', () => {
  const building = read('cloudflare/src/corporation-building-research-postgres.ts');
  const ui = read('flutter_client/lib/features/operations/technology_panel.dart');
  assert.match(building, /fundingSource: 'CORPORATION_OPERATIONS'/);
  assert.match(building, /canStart/);
  assert.match(building, /canPropose/);
  assert.match(ui, /START CORPORATION R&D/);
  assert.match(ui, /PROPOSE PUBLIC R&D/);
  assert.match(ui, /quoteCorporationBuildingResearch/);
});

test('Earth frontier constraints are authoritative and sequential', () => {
  const frontier = read('cloudflare/src/earth-technology-frontier-postgres.ts');
  const migration = read('db/migrations/123_v5_earth_technology_frontier.sql');
  const governance = read('cloudflare/src/proposal-actions.ts');
  assert.match(migration, /earth_technology_frontier_versions/);
  assert.match(frontier, /Technology generation exceeds the Earth frontier/);
  assert.match(frontier, /generationNumber !== frontier \+ 1/);
  assert.match(frontier, /authorization_proposal_id/);
  assert.match(governance, /Earth technology frontier action/);
});

test('research completion cannot create access outside the effective catalog/frontier contract', () => {
  const technology = read('cloudflare/src/technology-postgres.ts');
  const frontier = read('cloudflare/src/earth-technology-frontier-postgres.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(technology, /earth_assert_technology_research_allowed/);
  assert.match(technology, /earth_grant_corporation_technology_access/);
  assert.match(technology, /completed_game_day/);
  assert.match(frontier, /effective_from_game_day <= \$2/);
  assert.match(scheduler, /settlePatentExpirations/);
  assert.match(scheduler, /advanceV5ResearchProjects/);
});

test('retired Technology UI does not expose City, civic research, incremental funding, or legacy identifiers', () => {
  const panel = read('flutter_client/lib/features/operations/technology_panel.dart');
  const dialog = read('flutter_client/lib/features/operations/technology_dialogs.dart');
  const api = read('flutter_client/lib/core/api/earth_api_technology.dart');
  for (const source of [panel, dialog, api]) {
    assert.doesNotMatch(source, /PROPOSE CIVIC RESEARCH|SUBMIT CIVIC PROPOSAL|personal account/);
    assert.doesNotMatch(source, /fundResearch|Research parameter focus|Initial budget/);
    assert.doesNotMatch(source, /city_id|building_type.*legacy/);
  }
});
