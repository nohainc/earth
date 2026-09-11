import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const catalog = fs.readFileSync('cloudflare/src/real-estate-catalog.ts', 'utf8');
const contract = fs.readFileSync('docs/BUILDING_ECONOMY_CONTRACT.md', 'utf8');

test('every canonical building type has a documented economic loop', () => {
  const types = [...catalog.matchAll(/^  '([^']+)': \{/gm)].map((match) => match[1]);
  assert.equal(types.length, 15);
  for (const type of types) assert.ok(contract.includes(`\`${type}\``), `Missing documented building type: ${type}`);
});

test('the building contract uses capacity and explicit accounting, not service currencies', () => {
  for (const term of ['upkeep_energy', 'daily_operating_credits', 'Economy V2', 'customer-funded', 'House economic owner', 'completed game day']) assert.match(contract, new RegExp(term));
  assert.doesNotMatch(contract, /health token|internet token|education token|transport token|security token/);
});
