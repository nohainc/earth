import test from 'node:test';
import assert from 'node:assert/strict';

const PPM = 1_000_000n;
const RESOURCE_NAMES = ['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD'];

function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state;
  };
}

function ppmMultiply(left, right) {
  return (left * right + PPM / 2n) / PPM;
}

function cloneState(state) {
  return JSON.parse(JSON.stringify(state, (_, value) => typeof value === 'bigint' ? `${value}n` : value));
}

function toComparable(state) {
  return JSON.stringify(state, (_, value) => typeof value === 'bigint' ? `${value}n` : value);
}

function createScenario(seed, ownerCount = 24, buildingCount = 96) {
  const next = random(seed);
  const owners = Array.from({ length: ownerCount }, (_, index) => ({
    id: `OWNER-${index}`,
    credit: 100_000n,
    resources: Object.fromEntries(RESOURCE_NAMES.map((name) => [name, BigInt(80 + (next() % 180)) * PPM])),
  }));
  const source = Object.fromEntries(RESOURCE_NAMES.map((name) => [name, BigInt(ownerCount * 500) * PPM]));
  const sink = Object.fromEntries(RESOURCE_NAMES.map((name) => [name, 0n]));
  const buildings = Array.from({ length: buildingCount }, (_, index) => ({
    id: `BUILDING-${index}`,
    owner: index % ownerCount,
    priority: 1 + (next() % 3),
    conditionBp: BigInt(3_000 + (next() % 7_001)),
    baseOutput: RESOURCE_NAMES[(next() % RESOURCE_NAMES.length)],
    baseOutputUnits: BigInt(2 + (next() % 16)) * PPM,
    requirement: RESOURCE_NAMES[next() % RESOURCE_NAMES.length],
    requirementUnits: BigInt(2 + (next() % 12)) * PPM,
    service: index % 3 === 0,
    serviceCapacityUnits: BigInt(1 + (next() % 12)),
    servicePriceUnits: BigInt(5 + (next() % 20)),
    repairEnabled: index % 2 === 0,
    repairTargetBp: 9_000n,
    repairCostPerPointUnits: 100_000n,
  }));
  return { owners, buildings, source, sink, day: 0 };
}

function settleDay(state, seed, order = 'normal', shardCount = 1) {
  const effects = [];
  const creditAvailable = new Map(state.owners.map((owner, index) => [index, owner.credit]));
  const creditDeltas = new Map(state.owners.map((_, index) => [index, 0n]));
  // Demand is a building-local input, so derive it before traversal.  This
  // keeps shard assignment and input ordering from changing which building
  // receives a pseudo-random demand value.
  const demandByBuilding = new Map(state.buildings.map((building, index) => {
    const demandRandom = random(seed + state.day * 7919 + 104729 + index * 31337);
    return [
      building.id,
      BigInt(1 + (demandRandom() % Number(building.serviceCapacityUnits + 1n))),
    ];
  }));
  const ordered = [...state.buildings];
  const randomRank = new Map();
  if (order === 'reverse') ordered.reverse();
  if (order === 'random') {
    const ranked = ordered.map((building, index) => ({
      building,
      rank: random(seed + state.day * 7919 + 209759 + index * 31337)(),
    }));
    ranked.sort((a, b) => a.rank - b.rank || a.building.id.localeCompare(b.building.id));
    ordered.splice(0, ordered.length, ...ranked.map(({ building }) => building));
    ordered.forEach((building, index) => randomRank.set(building.id, index));
  }
  ordered.sort((a, b) => {
    const shardA = Number(BigInt(a.owner) % BigInt(shardCount));
    const shardB = Number(BigInt(b.owner) % BigInt(shardCount));
    if (shardA !== shardB) return shardA - shardB;
    if (order === 'reverse') return b.id.localeCompare(a.id);
    if (order === 'random') return randomRank.get(a.id) - randomRank.get(b.id);
    return a.id.localeCompare(b.id);
  });
  const byOwner = new Map();
  for (const building of ordered) {
    const list = byOwner.get(building.owner) ?? [];
    list.push(building);
    byOwner.set(building.owner, list);
  }

  for (const [ownerIndex, buildings] of byOwner) {
    const owner = state.owners[ownerIndex];
    const available = { ...owner.resources };
    buildings.sort((a, b) => a.priority - b.priority || a.id.localeCompare(b.id));
    for (const building of buildings) {
      const availableInput = available[building.requirement];
      const allocated = availableInput < building.requirementUnits ? availableInput : building.requirementUnits;
      const utilization = building.requirementUnits === 0n ? PPM : (allocated * PPM) / building.requirementUnits;
      const conditionEfficiency = building.conditionBp >= 2_000n ? (building.conditionBp * PPM) / 10_000n : 0n;
      const effectiveUtilization = utilization;
      const outputCapacity = ppmMultiply(ppmMultiply(building.baseOutputUnits, effectiveUtilization), conditionEfficiency);
      const consumed = ppmMultiply(building.requirementUnits, effectiveUtilization);
      available[building.requirement] -= consumed;
      owner.resources[building.requirement] -= consumed;
      state.sink[building.requirement] += consumed;
      const actualOutput = outputCapacity > 0n ? outputCapacity : 0n;
      state.source[building.baseOutput] -= actualOutput;
      owner.resources[building.baseOutput] += actualOutput;

      const wear = 25n + (PPM - effectiveUtilization) / 20_000n;
      const repairRequested = building.repairEnabled && building.conditionBp < building.repairTargetBp
        ? building.repairTargetBp - building.conditionBp : 0n;
      const repairResources = repairRequested * building.repairCostPerPointUnits / 10_000n;
      const repairApplied = repairResources > 0n
        ? (repairResources > owner.resources.COMPONENTS
          ? owner.resources.COMPONENTS * 10_000n / building.repairCostPerPointUnits
          : repairRequested)
        : 0n;
      const repairDebit = repairApplied * building.repairCostPerPointUnits / 10_000n;
      if (repairDebit > 0n) {
        owner.resources.COMPONENTS -= repairDebit;
        available.COMPONENTS -= repairDebit;
        state.sink.COMPONENTS += repairDebit;
      }
      building.conditionBp = building.conditionBp > wear ? building.conditionBp - wear : 0n;
      const repairedCondition = building.conditionBp + repairApplied;
      building.conditionBp = repairedCondition < building.repairTargetBp ? repairedCondition : building.repairTargetBp;
      assert.ok(building.conditionBp >= 0n && building.conditionBp <= 10_000n);
      assert.ok(repairApplied <= repairRequested);
      assert.ok(actualOutput <= ppmMultiply(building.baseOutputUnits, conditionEfficiency));

      if (building.service) {
        const requested = demandByBuilding.get(building.id);
        const sold = requested > building.serviceCapacityUnits ? building.serviceCapacityUnits : requested;
        const affordable = creditAvailable.get(ownerIndex) / building.servicePriceUnits;
        const paidUnits = sold > affordable ? affordable : sold;
        const payment = paidUnits * building.servicePriceUnits;
        creditAvailable.set(ownerIndex, creditAvailable.get(ownerIndex) - payment);
        const operatorIndex = (ownerIndex + 1) % state.owners.length;
        creditDeltas.set(ownerIndex, creditDeltas.get(ownerIndex) - payment);
        creditDeltas.set(operatorIndex, creditDeltas.get(operatorIndex) + payment);
        effects.push({ building: building.id, consumer: ownerIndex, operator: operatorIndex, payment });
      }
    }
  }

  // Payments are explicit owner-to-operator transfers; no service operation
  // creates CREDIT.
  for (const effect of effects) {
    assert.ok(effect.consumer !== effect.operator || effect.payment === 0n);
  }
  for (const owner of state.owners) {
    const index = state.owners.indexOf(owner);
    owner.credit += creditDeltas.get(index);
  }
  state.day += 1;
  return state;
}

function assertInvariants(state, initialTotals) {
  for (const owner of state.owners) {
    assert.ok(owner.credit >= 0n);
    for (const name of RESOURCE_NAMES) assert.ok(owner.resources[name] >= 0n, `${owner.id} ${name}=${owner.resources[name]}`);
  }
  for (const name of RESOURCE_NAMES) {
    const ownerTotal = state.owners.reduce((sum, owner) => sum + owner.resources[name], 0n);
    assert.equal(ownerTotal + state.source[name] + state.sink[name], initialTotals[name]);
  }
  const creditTotal = state.owners.reduce((sum, owner) => sum + owner.credit, 0n);
  assert.equal(creditTotal, initialTotals.CREDIT);
}

test('Building V2 property simulation preserves integer economic invariants', () => {
  for (const seed of [7, 42, 2026, 0xdeadbeef]) {
    const first = createScenario(seed);
    const initialTotals = Object.fromEntries(RESOURCE_NAMES.map((name) => [
      name,
      first.owners.reduce((sum, owner) => sum + owner.resources[name], 0n) + first.source[name] + first.sink[name],
    ]));
    initialTotals.CREDIT = first.owners.reduce((sum, owner) => sum + owner.credit, 0n);
    for (let day = 0; day < 30; day += 1) {
      settleDay(first, seed);
      assertInvariants(first, initialTotals);
    }
    const replay = createScenario(seed);
    for (let day = 0; day < 30; day += 1) settleDay(replay, seed);
    assert.equal(toComparable(replay), toComparable(first), `seed ${seed} must replay exactly`);
  }
});

test('Building V2 property fixtures cover shortages, repairs, and services', () => {
  const state = createScenario(123, 12, 48);
  assert.ok(state.buildings.some((building) => building.requirementUnits > 0n));
  assert.ok(state.buildings.some((building) => building.repairEnabled));
  assert.ok(state.buildings.some((building) => building.service));
  assert.ok(state.buildings.some((building) => building.conditionBp < 10_000n));
  // Ensure the fixture itself is serializable/replayable without floating state.
  assert.equal(toComparable(state), toComparable(JSON.parse(JSON.stringify(cloneState(state)))));
});

test('Building V2 settlement is invariant to input order and owner shard count', () => {
  const variants = [];
  for (const order of ['normal', 'reverse', 'random']) {
    for (const shardCount of [1, 4, 16]) {
      const state = createScenario(9081, 24, 96);
      for (let day = 0; day < 12; day += 1) settleDay(state, 9081, order, shardCount);
      variants.push({ order, shardCount, state: toComparable(state) });
    }
  }
  for (const variant of variants) {
    const expected = createScenario(9081, 24, 96);
    for (let day = 0; day < 12; day += 1) settleDay(expected, 9081, 'normal', 1);
    assert.equal(variant.state, toComparable(expected), `${variant.order}/${variant.shardCount} must match baseline`);
  }
});
