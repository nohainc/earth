import { RESOURCE_CODES, RESOURCE_FLOW_DEFINITIONS, SPECIALIZATIONS } from './resource-flow-definitions.mjs';

const STARTER = { CREDIT: 100_000, FOOD: 14, MATERIAL: 50, COMPONENTS: 0, ENERGY: 20, COMPUTE: 0 };
const BASE_PRICES = { MATERIAL: 40, COMPONENTS: 80, ENERGY: 20, COMPUTE: 50, FOOD: 12 };
const SCENARIOS = Object.freeze({
  baseline: {},
  'energy-shortage': { supply: { ENERGY: 0.35 } },
  'food-oversupply': { supply: { FOOD: 2.5 } },
  'compute-shortage': { demand: { COMPUTE: 2.5 } },
  'component-investment-boom': { construction: 3, boomStart: 30, boomEnd: 180 },
  'mass-new-player-arrival': { arrivals: 0.2, arrivalStart: 365, arrivalEnd: 730 },
  'generation-retrofit-boom': { construction: 3, boomStart: 3650, boomEnd: 4380 },
});

function rng(seed) {
  let value = seed >>> 0;
  return () => { value = (value * 1664525 + 1013904223) >>> 0; return value / 0x1_0000_0000; };
}

function emptyResources(value = 0) { return Object.fromEntries(RESOURCE_CODES.map((code) => [code, value])); }
function add(target, source, multiplier = 1) { for (const code of RESOURCE_CODES) target[code] += (source[code] ?? 0) * multiplier; }

function createCohorts(houses, specialization, random) {
  const names = Object.keys(SPECIALIZATIONS);
  const counts = Object.fromEntries(names.map((name) => [name, 0]));
  if (specialization === 'mixed') {
    for (let i = 0; i < houses; i += 1) counts[names[Math.floor(random() * names.length)]] += 1;
  } else counts[specialization] = houses;
  return Object.entries(counts).filter(([, count]) => count > 0).map(([name, count]) => ({
    name, houses: count, buildings: 0, inventory: { ...emptyResources(), ...STARTER }, credits: count * STARTER.CREDIT,
  }));
}

function outputTotals(cohorts) {
  const result = { production: emptyResources(), consumption: emptyResources(), inventory: emptyResources(), buildings: 0, credits: 0 };
  for (const cohort of cohorts) { add(result.inventory, cohort.inventory, 1); result.buildings += cohort.buildings; result.credits += cohort.credits; }
  return result;
}

export function runResourceEconomySimulation({ houses = 100, days = 365, seed = 42, specialization = 'mixed', scenario = 'baseline' } = {}) {
  if (!Number.isInteger(houses) || houses < 1 || !Number.isInteger(days) || days < 1) throw new Error('houses and days must be positive integers');
  if (!SCENARIOS[scenario]) throw new Error(`Unknown resource economy scenario: ${scenario}`);
  if (specialization !== 'mixed' && !SPECIALIZATIONS[specialization]) throw new Error(`Unknown specialization: ${specialization}`);
  const rules = SCENARIOS[scenario];
  const random = rng(seed);
  const cohorts = createCohorts(houses, specialization, random);
  const prices = { ...BASE_PRICES };
  const totals = { production: emptyResources(), consumption: emptyResources(), shortage: emptyResources(), inventoryGrowth: emptyResources() };
  const openingInventory = emptyResources();
  const priceSamples = Object.fromEntries(RESOURCE_CODES.map((code) => [code, 0]));
  const utilizationSamples = Object.fromEntries(RESOURCE_CODES.map((code) => [code, 0]));
  let trades = 0; let constructionStarted = 0; let survived = houses; let arrivals = 0; let shortageDays = 0;
  for (const code of RESOURCE_CODES) openingInventory[code] = cohorts.reduce((sum, cohort) => sum + cohort.inventory[code], 0);

  for (let day = 1; day <= days; day += 1) {
    if (rules.arrivals && day >= rules.arrivalStart && day <= rules.arrivalEnd) {
      const arriving = Math.max(1, Math.floor(houses * rules.arrivals / (rules.arrivalEnd - rules.arrivalStart + 1)));
      cohorts[0].houses += arriving; cohorts[0].credits += arriving * STARTER.CREDIT;
      for (const code of Object.keys(STARTER)) if (code !== 'CREDIT') cohorts[0].inventory[code] += arriving * STARTER[code];
      arrivals += arriving;
    }
    const constructionMultiplier = rules.construction && day >= rules.boomStart && day <= rules.boomEnd ? rules.construction : 1;
    let dayShortage = 0;
    for (const cohort of cohorts) {
      const specializationList = SPECIALIZATIONS[cohort.name];
      const catalog = RESOURCE_FLOW_DEFINITIONS[specializationList[(day + Math.floor(random() * specializationList.length)) % specializationList.length]];
      const targetBuildings = Math.max(1, Math.floor(cohort.houses * 0.35 * constructionMultiplier));
      if (cohort.buildings < targetBuildings && cohort.inventory.MATERIAL >= 10 && cohort.credits >= 1_000) {
        const canBuild = Math.min(targetBuildings - cohort.buildings, Math.floor(cohort.inventory.MATERIAL / 10), Math.floor(cohort.credits / 1_000));
        cohort.buildings += canBuild; cohort.inventory.MATERIAL -= canBuild * 10; cohort.credits -= canBuild * 1_000; constructionStarted += canBuild;
      }
      const scale = cohort.buildings * (rules.supply?.[Object.keys(catalog.outputs)[0]] ?? 1);
      const demand = emptyResources();
      for (const [code, units] of Object.entries(catalog.inputs)) demand[code] += units * scale;
      demand.FOOD += cohort.houses;
      for (const code of RESOURCE_CODES) {
        const available = cohort.inventory[code];
        const utilization = demand[code] > 0 ? Math.min(1, available / demand[code]) : 1;
        utilizationSamples[code] += utilization;
        const consumed = Math.floor(demand[code] * utilization);
        cohort.inventory[code] -= consumed; totals.consumption[code] += consumed;
        const shortage = Math.max(0, demand[code] - consumed); totals.shortage[code] += shortage; dayShortage += shortage;
        const output = catalog.outputs[code] ? Math.floor(catalog.outputs[code] * scale * utilization) : 0;
        cohort.inventory[code] += output; totals.production[code] += output;
      }
      // FOOD is a life-maintenance sink and is settled before production.
      cohort.inventory.FOOD = Math.max(0, cohort.inventory.FOOD);
      if (cohort.inventory.FOOD === 0 && cohort.houses > 0) { survived -= Math.min(cohort.houses, Math.ceil(cohort.houses * 0.01)); cohort.houses = Math.max(0, cohort.houses - Math.ceil(cohort.houses * 0.01)); }
      for (const code of RESOURCE_CODES) { const need = Math.max(1, demand[code]); const gap = Math.max(0, need - cohort.inventory[code]); if (gap > 0 && cohort.credits >= prices[code] * gap) { cohort.credits -= prices[code] * gap; cohort.inventory[code] += gap; trades += 1; } }
    }
    for (const code of RESOURCE_CODES) {
      const pressure = totals.production[code] / Math.max(1, totals.consumption[code] + totals.shortage[code]);
      prices[code] = Math.max(1, Math.min(10_000, prices[code] * (1 + Math.max(-0.08, Math.min(0.08, (1 - pressure) * 0.03)) + (random() - 0.5) * 0.005)));
      priceSamples[code] += prices[code];
    }
    if (dayShortage > 0) shortageDays += 1;
  }
  const final = outputTotals(cohorts);
  for (const code of RESOURCE_CODES) totals.inventoryGrowth[code] = final.inventory[code] - openingInventory[code];
  const averageUtilization = Object.fromEntries(RESOURCE_CODES.map((code) => [code, utilizationSamples[code] / days / Math.max(1, cohorts.length)]));
  const averagePrices = Object.fromEntries(RESOURCE_CODES.map((code) => [code, priceSamples[code] / days]));
  const wealth = cohorts.map((cohort) => cohort.credits + RESOURCE_CODES.reduce((sum, code) => sum + cohort.inventory[code] * prices[code], 0));
  const meanWealth = wealth.reduce((sum, value) => sum + value, 0) / Math.max(1, wealth.length);
  return { houses, arrivals, survivingHouses: survived, days, years: days / 365, seed, specialization, scenario, production: totals.production, consumption: totals.consumption, inventoryGrowth: totals.inventoryGrowth, shortage: totals.shortage, shortageFrequency: shortageDays / days, averagePrices, closingPrices: prices, averageUtilization, constructionStarted, trades, wealth: { mean: meanWealth, maxToMean: Math.max(...wealth, 0) / Math.max(1, meanWealth) } };
}

export const RESOURCE_SIMULATION_SCENARIOS = Object.keys(SCENARIOS);
