import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('House continuity integrity reports succession corruption', () => {
  const migration = read('db/migrations/313_house_continuity_integrity.sql');

  for (const check of [
    'house_without_exactly_one_current_active_human',
    'deceased_human_is_current_house_human',
    'human_without_valid_house',
    'house_generation_without_succession_event',
    'deceased_human_active_governance_role',
    'deceased_human_new_ballot',
    'duplicate_house_ballot',
    'market_order_invalid_house_owner',
    'bank_contract_invalid_house_owner',
    'private_building_invalid_house_owner',
    'deceased_human_equipped_heirloom',
  ]) assert.match(migration, new RegExp(check));

  assert.match(migration, /earth_integrity_report\(\)/);
  assert.match(migration, /earth_house_continuity_integrity\(\)/);
});
