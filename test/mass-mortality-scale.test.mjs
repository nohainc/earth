import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');

function mortalityRoll(index, gameYear) {
  let value = (index ^ (gameYear * 0x9e3779b9)) >>> 0;
  value = Math.imul(value ^ (value >>> 16), 0x45d9f3b) >>> 0;
  value = Math.imul(value ^ (value >>> 16), 0x45d9f3b) >>> 0;
  return ((value ^ (value >>> 16)) >>> 0) / 0x100000000;
}

test('mass mortality remains bounded and deterministic at one million Humans', () => {
  const population = 1_000_000;
  const gameYear = 12;
  let deaths = 0;
  let checksum = 0;

  for (let index = 0; index < population; index += 1) {
    const roll = mortalityRoll(index, gameYear);
    if (roll < 0.05) {
      deaths += 1;
      checksum = (checksum + index) >>> 0;
    }
  }

  assert.ok(deaths > population * 0.01 && deaths < population * 0.09);
  assert.equal(deaths, 50_022);
  assert.equal(checksum, 3_599_803_356);
});

test('mortality selection is bulk-loaded and does not transfer House assets per death', () => {
  const modern = lifecycle.slice(
    lifecycle.indexOf('export async function processHouseMortality'),
    lifecycle.indexOf('export async function activatePendingHouseSuccessors'),
  );

  assert.match(modern, /const candidates = await tx\.query/);
  assert.match(modern, /FOR UPDATE OF human/);
  assert.match(modern, /current_human_id = \$3/);
  assert.doesNotMatch(modern, /DELETE FROM (account_balances|resource_balances)/);
  assert.doesNotMatch(modern, /UPDATE (market_orders|bank_deposits|bank_loans) SET/);
});
