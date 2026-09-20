import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('World Program funding has bounded player contribution, matching, and refund contracts', async () => {
  const source = await readFile(new URL('../cloudflare/src/global-programs-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/069_global_program_funding_lifecycle.sql', import.meta.url), 'utf8');
  for (const term of ['funding_deadline_game_day', 'matching_authorized_units', 'global_program_contributions', 'GLOBAL_PROGRAM_CONTRIBUTION', 'GLOBAL_PROGRAM_REFUND', '10000n']) assert.match(`${source}\n${migration}`, new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(source, /owner_type = 'HOUSE'/);
  assert.match(source, /owner_economic_id = 'ECON-EARTH-001'/);
});

test('player contribution routes accept decimal CREDIT and convert exactly once at the API boundary', async () => {
  const routes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  const money = await readFile(new URL('../cloudflare/src/money.ts', import.meta.url), 'utf8');
  assert.match(routes, /parseCreditAmount\(parsed\.value\.amountCredit\)/);
  assert.match(routes, /amountCredit\?: string/);
  assert.match(money, /export function parseCreditAmount/);
  assert.match(money, /return moneyToCents\(value\)/);
});

test('initiative funding read models preserve contribution_units as atomic CREDIT units', async () => {
  const projects = await readFile(new URL('../cloudflare/src/public-projects-postgres.ts', import.meta.url), 'utf8');
  const panel = await readFile(new URL('../flutter_client/lib/features/world/public_projects_panel.dart', import.meta.url), 'utf8');
  assert.match(projects, /p\.contribution_units::TEXT/);
  assert.match(panel, /project\['contribution_units'\]/);
  assert.doesNotMatch(panel, /project\['contributed_units'\]/);
  assert.doesNotMatch(panel, /project\['funded_units'\]/);
});

test('legacy initiative creation and treasury funding are retired from player boundaries', async () => {
  const routes = await readFile(new URL('../cloudflare/src/read-model-routes.ts', import.meta.url), 'utf8');
  const registry = await readFile(new URL('../cloudflare/src/api-registry.ts', import.meta.url), 'utf8');
  const programsPanel = await readFile(new URL('../flutter_client/lib/features/world/world_programs_panel.dart', import.meta.url), 'utf8');
  const projectsPanel = await readFile(new URL('../flutter_client/lib/features/world/public_projects_panel.dart', import.meta.url), 'utf8');
  assert.match(routes, /Direct public-project creation is retired/);
  assert.match(routes, /Direct Earth-program creation is retired/);
  assert.match(routes, /Manual Earth treasury funding is retired/);
  assert.match(routes, /Manual matching-pool funding is retired/);
  assert.match(registry, /createGlobalProgram', status: 'RETIRED'/);
  assert.match(registry, /createPublicProject', status: 'RETIRED'/);
  assert.match(registry, /fundGlobalProgram', status: 'RETIRED'/);
  assert.match(registry, /fundMatchingPool', status: 'RETIRED'/);
  assert.doesNotMatch(programsPanel, /_createProgram|createGlobalProgram/);
  assert.doesNotMatch(projectsPanel, /_create\(|createPublicProject|fundPublicProjectMatchingPool|recipientAccountId/);
  assert.doesNotMatch(projectsPanel, /proposal_id|proposalId/);
});
