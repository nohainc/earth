import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');

function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

function integer(rng, max) {
  return Math.floor(rng() * (max + 1));
}

function makeHouse(seed) {
  const rng = random(seed);
  const houseId = `HOUSE-${seed}`;
  const humanId = `HUMAN-${seed}-1`;
  return {
    id: houseId,
    currentHumanId: humanId,
    generation: 1,
    balances: { CREDIT: integer(rng, 1_000_000), MATERIAL: integer(rng, 1_000_000), ENERGY: integer(rng, 1_000_000) },
    buildings: Array.from({ length: integer(rng, 8) }, (_, i) => `BUILDING-${seed}-${i}`),
    orders: Array.from({ length: integer(rng, 5) }, (_, i) => ({ id: `ORDER-${seed}-${i}`, escrow: integer(rng, 100_000) })),
    derivatives: Array.from({ length: integer(rng, 3) }, (_, i) => `POSITION-${seed}-${i}`),
    deposits: Array.from({ length: integer(rng, 3) }, (_, i) => `DEPOSIT-${seed}-${i}`),
    loans: Array.from({ length: integer(rng, 3) }, (_, i) => `LOAN-${seed}-${i}`),
    taxArrears: integer(rng, 100_000),
    memberships: [`CORP-${integer(rng, 4)}`, `CITY-${integer(rng, 4)}`],
    votes: Array.from({ length: integer(rng, 5) }, (_, i) => `PROPOSAL-${seed}-${i}`),
    roles: ['mayor', 'constitutional_judge', 'administrator'].filter(() => rng() > 0.45),
    heirlooms: Array.from({ length: integer(rng, 4) }, (_, i) => ({ id: `HEIRLOOM-${seed}-${i}`, equippedBy: humanId })),
    humans: [{ id: humanId, status: 'active' }],
  };
}

function succeedHouse(house) {
  const predecessor = house.currentHumanId;
  const successor = `${house.id}-GEN-${house.generation + 1}`;
  house.humans[0].status = 'deceased';
  house.currentHumanId = successor;
  house.generation += 1;
  house.humans.push({ id: successor, status: 'pending' });
  house.roles = [];
  house.heirlooms.forEach((heirloom) => { heirloom.equippedBy = null; });
  return { predecessor, successor };
}

test('random House succession changes representation, not economic conservation', () => {
  for (let seed = 1; seed <= 500; seed += 1) {
    const house = makeHouse(seed);
    const before = structuredClone(house);
    const { predecessor, successor } = succeedHouse(house);

    assert.ok(house.humans.filter((human) => human.status === 'active').length <= 1);
    assert.equal(house.humans.filter((human) => human.id === successor).length, 1);
    assert.equal(house.humans.filter((human) => human.id === predecessor && human.status === 'deceased').length, 1);
    assert.deepEqual(house.balances, before.balances);
    assert.deepEqual(house.buildings, before.buildings);
    assert.deepEqual(house.orders, before.orders);
    assert.deepEqual(house.derivatives, before.derivatives);
    assert.deepEqual(house.deposits, before.deposits);
    assert.deepEqual(house.loans, before.loans);
    assert.equal(house.taxArrears, before.taxArrears);
    assert.deepEqual(house.memberships, before.memberships);
    assert.deepEqual(house.votes, before.votes);
    assert.equal(new Set(house.votes).size, house.votes.length);
    assert.deepEqual(house.roles, []);
    assert.ok(house.heirlooms.every((heirloom) => heirloom.equippedBy !== predecessor));
  }
});

test('production mortality path preserves House-owned state and removes personal authority', () => {
  const modern = lifecycle.slice(lifecycle.indexOf('export async function processHouseMortality'), lifecycle.indexOf('export async function activatePendingHouseSuccessors'));
  assert.match(modern, /current_human_id = \$3/);
  assert.match(modern, /UPDATE house_heirlooms SET equipped_by_human_id = NULL/);
  assert.match(modern, /INSERT INTO governance_vacancies/);
  assert.match(modern, /ON CONFLICT \(house_id, generation\) DO NOTHING/);
  assert.doesNotMatch(modern, /DELETE FROM (account_balances|resource_balances)/);
  assert.doesNotMatch(modern, /UPDATE buildings SET/);
});
