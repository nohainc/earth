import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const DEFAULTS = {
  seed: 20260911,
  days: 365,
  houses: 10_000,
  buildingsPerHouse: 1.2,
  acceleration: 24,
};

function rng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function percentile(values, fraction) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * fraction))];
}

function topShare(values, fraction = 0.1) {
  const total = values.reduce((sum, value) => sum + value, 0);
  if (total <= 0) return 0;
  const top = [...values].sort((a, b) => b - a).slice(0, Math.max(1, Math.ceil(values.length * fraction)));
  return top.reduce((sum, value) => sum + value, 0) / total;
}

function gini(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const total = sorted.reduce((sum, value) => sum + value, 0);
  if (total <= 0 || sorted.length === 0) return 0;
  return (2 * sorted.reduce((sum, value, index) => sum + (index + 1) * value, 0)) /
      (sorted.length * total) - (sorted.length + 1) / sorted.length;
}

function snapshot(agents, cities, corporations, metrics, day) {
  const wealth = agents.map((agent) => agent.wallet);
  const corpWealth = corporations.map((corporation) => corporation.treasury);
  const actualCreditBalances = agents.reduce((sum, agent) => sum + agent.wallet, 0) +
      cities.reduce((sum, city) => sum + city.treasury, 0) +
      corporations.reduce((sum, corporation) => sum + corporation.treasury, 0);
  return {
    day,
    creditSupply: Number(actualCreditBalances.toFixed(6)),
    resourceTotals: { ...metrics.resources },
    creditSources: { issuance: metrics.issued, taxes: metrics.taxes, sales: metrics.sales },
    creditSinks: { retirement: metrics.retired, expenses: metrics.expenses, purchases: metrics.purchases },
    wealth: {
      median: Number(percentile(wealth, 0.5).toFixed(2)),
      p95: Number(percentile(wealth, 0.95).toFixed(2)),
      top10Share: Number(topShare(wealth).toFixed(4)),
      gini: Number(gini(wealth).toFixed(4)),
    },
    market: { ...metrics.market },
    buildingProfitability: Number((metrics.buildingRevenue / Math.max(1, metrics.buildingCount)).toFixed(2)),
    cityFinances: {
      medianTreasury: Number(percentile(cities.map((city) => city.treasury), 0.5).toFixed(2)),
      stressedCities: cities.filter((city) => city.treasury < 0).length,
    },
    corporationFinances: {
      medianTreasury: Number(percentile(corpWealth, 0.5).toFixed(2)),
      concentratedTop10Share: Number(topShare(corpWealth).toFixed(4)),
    },
    research: {
      completed: metrics.researchCompleted,
      medianProgress: Number(percentile(corporations.map((corporation) => corporation.research), 0.5).toFixed(2)),
    },
    humanNeeds: { averageSatisfaction: Number((metrics.needSatisfaction / (agents.length * Math.max(1, day))).toFixed(4)) },
  };
}

export function runClosedBetaSoak(options = {}) {
  const config = { ...DEFAULTS, ...options };
  if (!Number.isInteger(config.seed) || config.days < 1 || config.houses < 1) {
    throw new Error('seed must be an integer and days/houses must be positive');
  }
  const random = rng(config.seed);
  const corporationCount = Math.max(1, Math.ceil(config.houses / 100));
  const cityCount = Math.max(1, Math.ceil(config.houses / 250));
  const agents = Array.from({ length: config.houses }, (_, id) => ({
    id,
    wallet: 1_000,
    food: 100,
    energy: 100,
    corporation: id % corporationCount,
    satisfaction: 1,
  }));
  const corporations = Array.from({ length: corporationCount }, (_, id) => ({ id, treasury: 20_000, research: 0, technology: 0 }));
  const cities = Array.from({ length: cityCount }, (_, id) => ({ id, treasury: 50_000 }));
  const metrics = {
    issued: config.houses * 1_000 + corporationCount * 20_000 + cityCount * 50_000,
    retired: 0,
    taxes: 0,
    sales: 0,
    expenses: 0,
    purchases: 0,
    needSatisfaction: 0,
    researchCompleted: 0,
    buildingRevenue: 0,
    buildingCount: Math.round(config.houses * config.buildingsPerHouse),
    resources: { FOOD: config.houses * 100, ENERGY: config.houses * 100, MATERIAL: config.houses * 20, COMPONENTS: config.houses * 10, COMPUTE: config.houses * 5 },
    market: { FOOD: 10, ENERGY: 12, MATERIAL: 20, COMPONENTS: 30, COMPUTE: 40 },
  };
  const history = [];
  for (let day = 1; day <= config.days; day += 1) {
    const growth = 1 + (0.0008 * config.acceleration);
    let dayNeeds = 0;
    for (const agent of agents) {
      const corp = corporations[agent.corporation];
      const city = cities[agent.id % cityCount];
      const requestedIncome = 38 * growth * (1 + corp.technology * 0.01);
      // Income is a transfer from the corporation, not newly created CREDIT.
      const income = Math.min(requestedIncome, Math.max(0, corp.treasury));
      const foodCost = 8;
      const energyCost = 4;
      const tax = Math.max(0, income * 0.08);
      const serviceCost = 5;
      const spendableAfterTax = Math.max(0, agent.wallet + income - tax);
      const paidService = Math.min(serviceCost, spendableAfterTax);
      const spendableAfterService = spendableAfterTax - paidService;
      const paidFood = Math.min(foodCost, spendableAfterService);
      const paidEnergy = Math.min(energyCost, spendableAfterService - paidFood);
      corp.treasury -= income;
      agent.wallet = spendableAfterService - paidFood - paidEnergy;
      corp.treasury += tax * 0.25;
      corp.treasury += paidService;
      city.treasury += tax * 0.75;
      metrics.taxes += tax;
      metrics.sales += paidService;
      metrics.expenses += paidService;
      metrics.purchases += paidFood + paidEnergy;
      // Resource purchases are paid to the local market/service economy.
      city.treasury += paidFood + paidEnergy;
      agent.food = Math.max(0, agent.food + 10 - paidFood);
      agent.energy = Math.max(0, agent.energy + 6 - paidEnergy);
      const satisfaction = Math.min(1, (agent.food / 100 + agent.energy / 100) / 2) * (city.treasury > 0 ? 1 : 0.8);
      agent.satisfaction = satisfaction;
      dayNeeds += satisfaction;
      metrics.resources.FOOD += 10 - foodCost;
      metrics.resources.ENERGY += 6 - energyCost;
      metrics.resources.MATERIAL += 0;
      const output = 15 * growth * (1 + corp.technology * 0.015);
      const operatingCost = 4;
      // Building profitability is measured here, but its operating expense is
      // paid by the corporation and cannot create CREDIT by itself.
      const paidOperatingCost = Math.min(operatingCost, corp.treasury);
      corp.treasury -= paidOperatingCost;
      city.treasury += paidOperatingCost;
      metrics.buildingRevenue += output;
      metrics.expenses += operatingCost;
    }
    // One deterministic market movement per simulated day, rather than one
    // random walk per agent. This keeps the signal interpretable at scale.
    metrics.market.FOOD *= 1 + (random() - 0.5) * 0.01;
    metrics.market.ENERGY *= 1 + (random() - 0.5) * 0.01;
    for (const corporation of corporations) {
      corporation.research += 10 * (1 + corporation.technology * 0.02);
      if (corporation.research >= 1_000) {
        corporation.research -= 1_000;
        corporation.technology += 1;
        metrics.researchCompleted += 1;
      }
    }
    metrics.needSatisfaction += dayNeeds;
    history.push(snapshot(agents, cities, corporations, metrics, day));
  }
  const final = history.at(-1);
  const warnings = [];
  const initialShare = history[0].wealth.top10Share;
  if (final.wealth.top10Share - initialShare > 0.15) warnings.push('wealth concentration increased by more than 15 percentage points');
  if (final.corporationFinances.concentratedTop10Share > 0.75) warnings.push('corporate treasury concentration exceeds 75%');
  if (final.humanNeeds.averageSatisfaction < 0.5) warnings.push('average human need satisfaction is below 50%');
  if (final.cityFinances.stressedCities > 0) warnings.push('one or more cities entered negative treasury');
  return { config, summary: { final, warnings, creditConserved: Math.abs(final.creditSupply - (metrics.issued - metrics.retired)) < 0.01, nonNegative: agents.every((agent) => agent.wallet >= 0) }, history };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const report = runClosedBetaSoak({
    seed: Number(process.env.EARTH_SOAK_SEED ?? DEFAULTS.seed),
    days: Number(process.env.EARTH_SOAK_DAYS ?? DEFAULTS.days),
    houses: Number(process.env.EARTH_SOAK_HOUSES ?? DEFAULTS.houses),
    acceleration: Number(process.env.EARTH_SOAK_ACCELERATION ?? DEFAULTS.acceleration),
  });
  const output = process.env.EARTH_SOAK_OUTPUT;
  if (output) await writeFile(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ soak: 'closed-beta', ...report.summary, output: output ?? null }, null, 2));
}
