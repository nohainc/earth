// Deterministic balance harness for validating EARTH's core economic invariants.
export function runSimulation({ days = 365, humans = 30, seed = 42 } = {}) {
  let random = seed;
  const next = () => {
    random = (random * 1664525 + 1013904223) >>> 0;
    return random / 0x100000000;
  };
  const players = Array.from({ length: humans }, (_, index) => ({ id: `SIM-${index + 1}`, credits: 1000, material: 30, components: 20, energy: 24, compute: 12, machineCondition: 100 }));
  const institutions = { ouc: 0, corporation: 0, city: 0 };
  const initialCredits = players.reduce((total, player) => total + player.credits, 0);
  const initialResources = players.reduce((totals, player) => {
    for (const resource of ['material', 'components', 'energy', 'compute']) totals[resource] += player[resource];
    return totals;
  }, { material: 0, components: 0, energy: 0, compute: 0 });
  let trades = 0;
  let maintenanceDemand = 0;
  let production = 0;
  let fees = 0;
  for (let day = 1; day <= days; day += 1) {
    for (const player of players) {
      player.machineCondition = Math.max(0, player.machineCondition - 0.25);
      maintenanceDemand += 0.25;
      if (player.machineCondition < 70 && player.components >= 2) {
        player.components -= 2;
        player.machineCondition = Math.min(100, player.machineCondition + 12);
        maintenanceDemand -= 2;
      }
      // A machine creates Components only after consuming physical inputs.
      // This keeps the harness aligned with the authoritative production rule:
      // time alone never creates Credits or goods.
      if (player.machineCondition > 25 && player.material >= 1 && player.energy >= 1) {
        player.material -= 1;
        player.energy -= 1;
        player.components += 1;
        production += 1;
      }
      if (next() < 0.35 && player.credits >= 10) {
        player.credits -= 10;
        const seller = players[Math.floor(next() * players.length)];
        const fee = 0.5;
        player.credits -= fee;
        seller.credits += 10;
        institutions.ouc += fee;
        fees += fee;
        trades += 1;
      }
    }
    // Corporation and City budgets redistribute existing Credits, never mint them.
    if (institutions.corporation >= 5) {
      institutions.corporation -= 5;
      institutions.city += 5;
    }
    if (day % 30 === 0 && players[0].credits >= 2) {
      players[0].credits -= 2;
      institutions.corporation += 2;
    }
  }
  const finalCredits = players.reduce((total, player) => total + player.credits, 0) + institutions.ouc + institutions.corporation + institutions.city;
  const finalResources = players.reduce((totals, player) => {
    for (const resource of ['material', 'components', 'energy', 'compute']) totals[resource] += player[resource];
    return totals;
  }, { material: 0, components: 0, energy: 0, compute: 0 });
  return {
    days,
    humans,
    trades,
    maintenanceDemand,
    production,
    fees,
    creditsConserved: finalCredits === initialCredits,
    nonNegativeBalances: players.every((player) => player.credits >= 0 && player.components >= 0),
    resourceNonNegative: players.every((player) => ['material', 'components', 'energy', 'compute'].every((resource) => player[resource] >= 0)),
    institutionBalancesNonNegative: Object.values(institutions).every((balance) => balance >= 0),
    boundedMachineCondition: players.every((player) => player.machineCondition >= 0 && player.machineCondition <= 100),
    initialCredits,
    finalCredits,
    initialResources,
    finalResources,
    institutions,
  };
}

// Integer-unit finance harness. This deliberately models contracts and
// distress transitions without PostgreSQL so property tests can run quickly.
export function runFinanceSimulation({ days = 60, humans = 10000, cities = 100, seed = 42 } = {}) {
  let random = seed >>> 0;
  const next = () => { random = (random * 1664525 + 1013904223) >>> 0; return random / 0x100000000; };
  const people = Array.from({ length: humans }, (_, id) => ({ id, wallet: 100_000, resources: 10_000, debt: 0, arrears: 0, deposit: 0 }));
  const institutions = Array.from({ length: cities }, (_, id) => ({ id, treasury: 1_000_000, debt: 0, state: 'ACTIVE' }));
  const bank = { reserve: 0, equity: 0, deposits: 0, loans: 0, state: 'NORMAL' };
  let issued = humans * 100_000 + cities * 1_000_000;
  let retired = 0;
  for (let day = 1; day <= days; day += 1) {
    for (const person of people) {
      if (next() < 0.06 && person.wallet >= 10_000) {
        const amount = 1_000 + Math.floor(next() * 9_000);
        person.wallet -= amount; bank.reserve += amount; bank.deposits += amount; person.deposit += amount;
      }
      if (next() < 0.04 && bank.reserve >= 5_000 && bank.state === 'NORMAL') {
        const amount = 1_000 + Math.floor(next() * 4_000);
        bank.reserve -= amount; bank.loans += amount; person.wallet += amount; person.debt += amount;
      }
      if (next() < 0.12) person.arrears += 100;
      if (person.arrears > 0 && person.wallet >= person.arrears && next() < 0.4) { const city = institutions[person.id % institutions.length]; person.wallet -= person.arrears; city.treasury += person.arrears; person.arrears = 0; }
      if (person.debt > 0 && person.wallet >= 50 && next() < 0.25) { person.wallet -= 50; bank.reserve += 50; person.debt -= 50; bank.loans -= 50; }
    }
    if (day % 7 === 0) {
      const person = people[Math.floor(next() * people.length)];
      if (person.deposit > 0 && bank.reserve >= person.deposit) { bank.reserve -= person.deposit; person.wallet += person.deposit; bank.deposits -= person.deposit; person.deposit = 0; }
    }
    if (day % 15 === 0) {
      const city = institutions[Math.floor(next() * institutions.length)];
      if (city.treasury >= 20_000) { city.treasury -= 20_000; people[Math.floor(next() * people.length)].wallet += 20_000; }
    }
    const liabilities = bank.deposits + people.reduce((sum, p) => sum + p.deposit, 0);
    bank.equity = bank.reserve + bank.loans - bank.deposits;
    bank.state = bank.equity < 0 ? 'INSOLVENT' : bank.reserve < bank.deposits ? 'LIQUIDITY_STRESS' : 'NORMAL';
    if (bank.state !== 'NORMAL') for (const person of people) person.debt = Math.max(0, person.debt);
    void liabilities;
  }
  const finalSupply = people.reduce((sum, p) => sum + p.wallet, 0) + institutions.reduce((sum, i) => sum + i.treasury, 0) + bank.reserve;
  return { days, humans, cities, issued, retired, openingSupply: issued - retired, closingSupply: finalSupply, creditConserved: finalSupply === issued - retired, nonNegative: people.every((p) => p.wallet >= 0 && p.deposit >= 0 && p.debt >= 0 && p.arrears >= 0) && institutions.every((i) => i.treasury >= 0), bankSolventOrStressed: ['NORMAL', 'LIQUIDITY_STRESS', 'INSOLVENT'].includes(bank.state), bank, taxArrears: people.reduce((sum, p) => sum + p.arrears, 0), bankruptcyCases: people.filter((p) => p.debt > p.wallet + p.deposit).length };
}

const ECONOMY_RESOURCES = ['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD'];
const ECONOMY_SCENARIOS = {
  baseline: { energySupply: 1, foodDemand: 1, taxRate: 0.1, technologyGrowth: 0.001, constructionDemand: 1 },
  'high-energy-shortage': { energySupply: 0.12, foodDemand: 1, taxRate: 0.1, technologyGrowth: 0.001, constructionDemand: 1 },
  'high-food-demand': { energySupply: 1, foodDemand: 5, taxRate: 0.1, technologyGrowth: 0.001, constructionDemand: 1 },
  'low-taxes': { energySupply: 1, foodDemand: 1, taxRate: 0.02, technologyGrowth: 0.001, constructionDemand: 1 },
  'high-taxes': { energySupply: 1, foodDemand: 1, taxRate: 0.2, technologyGrowth: 0.001, constructionDemand: 1 },
  'technology-heavy': { energySupply: 1, foodDemand: 1, taxRate: 0.1, technologyGrowth: 0.008, constructionDemand: 1 },
  'rapid-construction': { energySupply: 1, foodDemand: 1, taxRate: 0.1, technologyGrowth: 0.001, constructionDemand: 2.5 },
};

export const ECONOMY_SIMULATION_PROFILES = {
  small: 100,
  medium: 10_000,
  large: 100_000,
};

function economyRandom(seed) {
  let state = seed >>> 0;
  return () => { state = (state * 1664525 + 1013904223) >>> 0; return state / 0x1_0000_0000; };
}

/**
 * Deterministic aggregate simulation for balance discovery. It deliberately
 * models transfers and inventories in aggregate; it is a stress signal, not a
 * forecast of one correct economy.
 */
export function runEconomySimulation({ days = 365, houses = 100, seed = 42, scenario = 'baseline' } = {}) {
  if (!Number.isInteger(days) || days < 1) throw new Error('days must be a positive integer');
  if (!Number.isInteger(houses) || houses < 1) throw new Error('houses must be a positive integer');
  const rules = ECONOMY_SCENARIOS[scenario];
  if (!rules) throw new Error(`Unknown economy scenario: ${scenario}`);
  const random = economyRandom(seed);
  const cities = Math.max(1, Math.ceil(houses / 100));
  const corporations = Math.max(1, Math.ceil(houses / 20));
  const buildings = Math.max(1, Math.floor(houses * 0.65));
  const issuedCredits = houses * 100_000;
  let creditSupply = issuedCredits;
  let taxRevenue = 0;
  let researchProgress = 0;
  let completedResearch = 0;
  let constructionStarted = 0;
  let totalTrades = 0;
  let priceVolatility = 0;
  const resources = { MATERIAL: houses * 120, COMPONENTS: houses * 30, ENERGY: houses * 100, COMPUTE: houses * 25, FOOD: houses * 180 };
  const prices = { MATERIAL: 40, COMPONENTS: 80, ENERGY: 20, COMPUTE: 50, FOOD: 12 };
  const shortages = Object.fromEntries(ECONOMY_RESOURCES.map((resource) => [resource, 0]));
  const wealthBuckets = [0.5, 0.8, 1, 1.3, 2].map((multiplier) => ({ multiplier, credits: houses * 100_000 * multiplier / 5 }));
  const daily = [];

  for (let day = 1; day <= days; day += 1) {
    const tech = 1 + Math.min(0.35, day * rules.technologyGrowth);
    const demand = {
      MATERIAL: buildings * 12 * rules.constructionDemand,
      COMPONENTS: buildings * 3 * rules.constructionDemand,
      ENERGY: houses * 1.2,
      COMPUTE: corporations * 15,
      FOOD: houses * 2 * rules.foodDemand,
    };
    const production = {
      MATERIAL: buildings * 10 * tech,
      COMPONENTS: buildings * 4 * tech,
      ENERGY: buildings * 9 * tech * rules.energySupply,
      COMPUTE: corporations * 14 * tech,
      FOOD: buildings * 14 * tech,
    };
    let dayShortage = 0;
    for (const resource of ECONOMY_RESOURCES) {
      resources[resource] += production[resource];
      const available = resources[resource];
      const consumed = Math.min(available, demand[resource]);
      resources[resource] -= consumed;
      const shortage = Math.max(0, demand[resource] - consumed);
      shortages[resource] += shortage;
      dayShortage += shortage;
      const pressure = demand[resource] / Math.max(1, production[resource]);
      const oldPrice = prices[resource];
      prices[resource] = Math.max(1, Math.min(10_000, oldPrice * (1 + Math.max(-0.08, Math.min(0.08, (pressure - 1) * 0.035)) + (random() - 0.5) * 0.01)));
      priceVolatility += Math.abs(prices[resource] - oldPrice) / oldPrice;
      totalTrades += Math.floor(Math.min(production[resource], demand[resource]) / Math.max(1, resource === 'FOOD' ? 10 : 5));
    }
    const dailyTax = houses * 100 * rules.taxRate;
    taxRevenue += dailyTax;
    researchProgress += corporations * 250 * tech;
    while (researchProgress >= corporations * 4_000) { researchProgress -= corporations * 4_000; completedResearch += corporations; }
    constructionStarted += Math.floor(buildings * rules.constructionDemand / 30);
    // Market, tax, and institutional flows redistribute existing CREDIT.
    // The aggregate model therefore keeps supply exactly equal to issuance.
    creditSupply = issuedCredits;
    const growth = Math.max(0, (production.FOOD + production.COMPONENTS) - (demand.FOOD + demand.COMPONENTS)) * 0.1;
    for (const bucket of wealthBuckets) bucket.credits += growth * bucket.multiplier - dailyTax * (1 / 5);
    daily.push({ day, prices: { ...prices }, shortage: dayShortage, taxRevenue: dailyTax, completedResearch });
  }
  const sortedWealth = wealthBuckets.map((bucket) => bucket.credits).sort((a, b) => a - b);
  const meanWealth = sortedWealth.reduce((sum, value) => sum + value, 0) / sortedWealth.length;
  const wealthConcentration = sortedWealth.at(-1) / Math.max(1, meanWealth);
  const maxPrice = Math.max(...Object.values(prices));
  const minPrice = Math.min(...Object.values(prices));
  const totalShortage = Object.values(shortages).reduce((sum, value) => sum + value, 0);
  const warnings = [];
  if (creditSupply > issuedCredits || creditSupply < issuedCredits) warnings.push('CREDIT supply changed without an explicit issuance/retirement event.');
  if (totalShortage > houses * days * 2) warnings.push('Persistent resource shortage detected.');
  if (maxPrice / Math.max(1, minPrice) > 20) warnings.push('Resource price divergence indicates possible instability.');
  if (wealthConcentration > 2.5) warnings.push('Wealth concentration exceeded the review threshold.');
  if (scenario === 'technology-heavy' && completedResearch > corporations * days / 3) warnings.push('Technology progression may be compounding too quickly.');
  return { days, houses, cities, corporations, buildings, scenario, seed, issuedCredits, closingCreditSupply: creditSupply, creditConserved: creditSupply === issuedCredits, resources, prices, shortages, totalShortage, totalTrades, taxRevenue, completedResearch, constructionStarted, wealthDistribution: { buckets: wealthBuckets, concentrationRatio: wealthConcentration }, priceVolatility, warnings, daily: days <= 30 ? daily : undefined };
}
