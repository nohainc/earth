import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('Corporation lifecycle is defined as Corporation plus primary Territory plus House affiliation', () => {
  const source = read('cloudflare/src/institutions-postgres.ts');
  assert.match(source, /export async function createCorporation/);
  assert.match(source, /INSERT INTO institutions \(id, kind, name, status\)[\s\S]*'CORPORATION'/);
  assert.match(source, /INSERT INTO territories/);
  assert.match(source, /is_primary/);
  assert.match(source, /INSERT INTO house_affiliations/);
  assert.match(source, /primary_territory_id/);
  assert.match(source, /export async function changeCorporationMembership/);
  assert.match(source, /status = 'LEFT'/);
  assert.match(source, /left_game_day/);
});

test('Corporation lifecycle has no City formation prerequisite or compatibility query', () => {
  const source = read('cloudflare/src/institutions-postgres.ts');
  assert.doesNotMatch(source, /cities|city_id|capital_city|resident|30 active/i);
  assert.doesNotMatch(source, /CREATE TABLE|CREATE VIEW/);
});
