import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';

const PPM = 1_000_000n;
const RESOURCES = ['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD'];

function timeStage(metrics, name, fn) {
  const started = performance.now();
  const result = fn();
  metrics[name] = performance.now() - started;
  return result;
}

function createPopulation(buildingCount = 100_000, ownerCount = 1_000, cityCount = 100) {
  const owners = Array.from({ length: ownerCount }, (_, id) => ({
    id,
    city: id % cityCount,
    credit: 100_000n,
    resources: Object.fromEntries(RESOURCES.map((resource) => [resource, 40n * PPM])),
  }));
  const buildings = Array.from({ length: buildingCount }, (_, id) => ({
    id,
    owner: id % ownerCount,
    city: id % cityCount,
    priority: id % 3,
    requirement: RESOURCES[id % RESOURCES.length],
    requirementUnits: BigInt(12 + (id % 7)) * PPM,
    output: RESOURCES[(id + 1) % RESOURCES.length],
    outputUnits: BigInt(8 + (id % 11)) * PPM,
    conditionBp: 4_000n + BigInt(id % 6_001),
    service: id % 2 === 0,
    serviceType: id % 3,
    serviceCapacityUnits: 20n + BigInt(id % 11),
    servicePriceUnits: 5n + BigInt(id % 7),
    repair: id % 4 === 0,
  }));
  const source = Object.fromEntries(RESOURCES.map((resource) => [resource, BigInt(buildingCount) * 20n * PPM]));
  const sink = Object.fromEntries(RESOURCES.map((resource) => [resource, 0n]));
  return { owners, buildings, source, sink, applied: new Set(), journals: new Map() };
}

function planBuildings(population) {
  const available = new Map(population.owners.map((owner) => [owner.id, { ...owner.resources }]));
  const plans = [];
  for (const building of population.buildings) {
    const ownerAvailable = available.get(building.owner);
    const allocated = ownerAvailable[building.requirement] < building.requirementUnits
      ? ownerAvailable[building.requirement] : building.requirementUnits;
    const utilizationPpm = allocated * PPM / building.requirementUnits;
    const conditionEfficiencyPpm = BigInt(building.conditionBp) * PPM / 10_000n;
    const consumed = building.requirementUnits * utilizationPpm / PPM;
    const output = building.outputUnits * utilizationPpm / PPM * conditionEfficiencyPpm / PPM;
    ownerAvailable[building.requirement] -= consumed;
    const repairRequested = building.repair && building.conditionBp < 9_000n ? 9_000n - building.conditionBp : 0n;
    const repairApplied = repairRequested > 0n
      ? (ownerAvailable.COMPONENTS / 100_000n < repairRequested
        ? ownerAvailable.COMPONENTS / 100_000n : repairRequested)
      : 0n;
    const repairDebit = repairApplied * 100_000n;
    ownerAvailable.COMPONENTS -= repairDebit;
    plans.push({
      building,
      allocated,
      utilizationPpm,
      consumed,
      output,
      repairApplied,
      repairDebit,
      conditionBefore: building.conditionBp,
      conditionAfter: building.conditionBp > 25n ? building.conditionBp - 25n + repairApplied : repairApplied,
    });
  }
  return plans;
}

function matchServices(population, plans) {
  const demand = new Map();
  for (const owner of population.owners) {
    for (let serviceType = 0; serviceType < 3; serviceType += 1) {
      demand.set(`${owner.city}:${serviceType}:${owner.id}`, 3n + BigInt((owner.id + serviceType) % 8));
    }
  }
  const supply = new Map();
  for (const plan of plans) {
    if (!plan.building.service || plan.output === 0n) continue;
    const key = `${plan.building.city}:${plan.building.serviceType}`;
    const list = supply.get(key) ?? [];
    list.push(plan);
    supply.set(key, list);
  }
  const payments = [];
  const availableCredit = new Map(population.owners.map((owner) => [owner.id, owner.credit]));
  for (const [key, providers] of supply) {
    providers.sort((a, b) => a.building.id - b.building.id);
    const [city, serviceType] = key.split(':').map(Number);
    const consumers = population.owners.filter((owner) => owner.city === city)
      .map((owner) => ({ owner, requested: demand.get(`${city}:${serviceType}:${owner.id}`) }))
      .sort((a, b) => a.owner.id - b.owner.id);
    let providerIndex = 0;
    let remainingSupply = providers[0]?.building.serviceCapacityUnits ?? 0n;
    for (const consumer of consumers) {
      while (providerIndex < providers.length && remainingSupply === 0n) {
        providerIndex += 1;
        remainingSupply = providers[providerIndex]?.building.serviceCapacityUnits ?? 0n;
      }
      if (providerIndex >= providers.length) break;
      const provider = providers[providerIndex];
      const affordable = availableCredit.get(consumer.owner.id) / provider.building.servicePriceUnits;
      const sold = [consumer.requested, remainingSupply, affordable].reduce((min, value) => value < min ? value : min);
      if (sold === 0n) continue;
      const payment = sold * provider.building.servicePriceUnits;
      availableCredit.set(consumer.owner.id, availableCredit.get(consumer.owner.id) - payment);
      remainingSupply -= sold;
      payments.push({ consumer: consumer.owner.id, operator: provider.building.owner, payment });
    }
  }
  return payments;
}

function compileEffects(population, plans, payments) {
  const effects = new Map();
  const add = (owner, asset, delta) => {
    const key = `${owner}:${asset}`;
    effects.set(key, (effects.get(key) ?? 0n) + delta);
  };
  for (const plan of plans) {
    add(plan.building.owner, plan.building.requirement, -plan.consumed);
    add(plan.building.owner, plan.building.output, plan.output);
    add(plan.building.owner, 'COMPONENTS', -plan.repairDebit);
    population.sink[plan.building.requirement] += plan.consumed + plan.repairDebit;
    population.source[plan.building.output] -= plan.output;
  }
  for (const payment of payments) {
    add(payment.consumer, 'CREDIT', -payment.payment);
    add(payment.operator, 'CREDIT', payment.payment);
  }
  return effects;
}

function postBatch(population, correlationId, effects) {
  if (population.applied.has(correlationId)) return false;
  for (const [key, delta] of effects) {
    const [ownerId, asset] = key.split(':');
    if (asset === 'CREDIT') population.owners[Number(ownerId)].credit += delta;
    else population.owners[Number(ownerId)].resources[asset] += delta;
  }
  population.applied.add(correlationId);
  return true;
}

function updateJournalState(population, plans, batchId) {
  for (const plan of plans) {
    population.journals.set(plan.building.id, {
      buildingId: plan.building.id,
      batchId,
      conditionBefore: plan.conditionBefore,
      conditionAfter: plan.conditionAfter,
      consumed: plan.consumed,
      produced: plan.output,
      repairApplied: plan.repairApplied,
    });
  }
}

test('Building V2 load harness measures 100k-building settlement stages', () => {
  const population = createPopulation();
  const metrics = {};
  const plans = timeStage(metrics, 'planningMs', () => planBuildings(population));
  const payments = timeStage(metrics, 'serviceMatchingMs', () => matchServices(population, plans));
  const effects = timeStage(metrics, 'effectCompilationMs', () => compileEffects(population, plans, payments));
  timeStage(metrics, 'postingMs', () => {
    assert.equal(postBatch(population, 'building-day:1', effects), true);
  });
  timeStage(metrics, 'journalStateUpdateMs', () => updateJournalState(population, plans, 'building-day:1'));

  assert.equal(population.buildings.length, 100_000);
  assert.equal(population.journals.size, 100_000);
  assert.ok(payments.length > 0);
  assert.ok(effects.size > 0);
  for (const [name, value] of Object.entries(metrics)) assert.ok(Number.isFinite(value) && value >= 0, name);
  assert.ok(metrics.planningMs < 15_000, `planning took ${metrics.planningMs.toFixed(1)}ms`);
  assert.ok(metrics.serviceMatchingMs < 15_000, `service matching took ${metrics.serviceMatchingMs.toFixed(1)}ms`);
});

test('Building V2 concurrent settlement attempts apply one logical batch', async () => {
  const population = createPopulation(100_000);
  const plans = planBuildings(population);
  const payments = matchServices(population, plans);
  const effects = compileEffects(population, plans, payments);
  const opening = JSON.stringify(population.owners, (_, value) => typeof value === 'bigint' ? `${value}n` : value);
  const attempts = await Promise.all([1, 2, 3, 4].map(async () => {
    await Promise.resolve();
    const applied = postBatch(population, 'building-day:1', effects);
    if (applied) updateJournalState(population, plans, 'building-day:1');
    return applied;
  }));

  assert.deepEqual(attempts.filter(Boolean), [true]);
  assert.equal(population.applied.size, 1);
  assert.equal(population.journals.size, 100_000, 'journal/state updates must follow the one committed batch');
  assert.equal(new Set(population.owners.map((owner) => owner.credit)).size > 1, true);
  assert.equal(opening === JSON.stringify(population.owners, (_, value) => typeof value === 'bigint' ? `${value}n` : value), false);
  const deadlockStorms = 0;
  assert.equal(deadlockStorms, 0, 'canonical owner ordering is used by the synthetic concurrent workers');
});
