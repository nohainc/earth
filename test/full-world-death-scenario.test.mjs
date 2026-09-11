import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('full-world death scenario preserves House-owned economy and contracts', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const market = read('cloudflare/src/market-postgres.ts');
  const bank = read('cloudflare/src/global-bank-postgres.ts');
  const financeSchema = read('db/migrations/216_bank_loans_v2.sql');
  const governance = read('cloudflare/src/governance-postgres.ts');
  const building = read('cloudflare/src/building-settlement-v2.ts');
  const technology = read('cloudflare/src/technology-postgres.ts');
  const house = read('cloudflare/src/house-postgres.ts');
  const houseMortality = lifecycle.slice(
    lifecycle.indexOf('export async function processHouseMortality'),
    lifecycle.indexOf('export async function activatePendingHouseSuccessors'),
  );

  // Simple death: create a new Human while keeping the House/economic owner.
  assert.match(houseMortality, /INSERT INTO humans/);
  assert.match(houseMortality, /current_human_id = \$3/);
  assert.match(houseMortality, /owner_registry/);
  assert.doesNotMatch(houseMortality, /DELETE FROM (account_balances|resource_balances)/);
  assert.doesNotMatch(houseMortality, /UPDATE buildings SET/);

  // Market orders and escrow remain tied to economic owners.
  assert.match(market, /owner_economic_id/);
  assert.match(market, /owner\.economic_id FROM humans JOIN owner_registry owner ON owner\.id = humans\.house_id/);

  // Deposits, loans, and obligations are House-owned contracts.
  assert.match(bank, /earth_private_economic_owner_id/);
  assert.match(bank, /depositor_economic_id/);
  assert.match(financeSchema, /borrower_economic_id/);

  // Votes remain House-unique; Human authorship and offices remain personal.
  assert.match(governance, /proposal_id, house_id, human_id/);
  assert.match(governance, /ON CONFLICT \(proposal_id, house_id\) DO NOTHING/);
  assert.match(houseMortality, /INSERT INTO governance_vacancies/);
  assert.match(houseMortality, /administrator_human_id = NULL/);

  // House-owned buildings continue to resolve corporation technology normally.
  assert.match(building, /owner_economic_id/);
  assert.match(building, /earth_building_corporation_economic_id/);
  assert.match(technology, /corporationEconomicId/);

  // House perks survive; only the deceased Human's equipment assignment is cleared.
  assert.match(house, /house_perks/);
  assert.match(house, /house_heirlooms/);
  assert.match(houseMortality, /equipped_by_human_id = NULL/);
});
