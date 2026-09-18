import { RESOURCE_CODES, RESOURCE_FLOW_DEFINITIONS } from './resource-flow-definitions.mjs';

export const V5_RESOURCE_CODES = Object.freeze(['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD']);

export const V5_BASE_PRICES = Object.freeze({
  MATERIAL: 40,
  COMPONENTS: 80,
  ENERGY: 20,
  COMPUTE: 50,
  FOOD: 12,
});

export const V5_STARTER = Object.freeze({
  CREDIT: 100_000,
  FOOD: 30,
  MATERIAL: 50,
  COMPONENTS: 10,
  ENERGY: 40,
  COMPUTE: 10,
});

export const V5_BUILDING_TIERS = Object.freeze({
  1: { creditCost: 5_000, materialCost: 20, componentCost: 5, footprint: 1, operatingCredit: 10 },
  2: { creditCost: 15_000, materialCost: 60, componentCost: 25, footprint: 2, operatingCredit: 25 },
  3: { creditCost: 45_000, materialCost: 180, componentCost: 80, footprint: 4, operatingCredit: 60 },
  4: { creditCost: 120_000, materialCost: 500, componentCost: 250, footprint: 8, operatingCredit: 150 },
});

export const V5_SCENARIOS = Object.freeze([
  'all-houses-choose-energy',
  'all-houses-choose-food',
  'corporation-material-monopoly',
  'energy-shortage',
  'compute-shortage',
  'excess-material',
  'excess-components',
  'low-rent',
  'progressive-rent',
  'many-small-corporations',
  'one-mega-corporation',
  'inactive-players',
  'bankrupt-producers',
  'construction-boom',
  'stalled-construction',
  'independent-heavy',
  'baseline',
]);

function rng(seed = 42) {
  let value = seed >>> 0;
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0;
    return value / 0x1_0000_0000;
  };
}

function emptyResources(val = 0) {
  return Object.fromEntries(V5_RESOURCE_CODES.map((c) => [c, val]));
}

function calculateGini(values) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  let sum = 0;
  let weightedSum = 0;
  for (let i = 0; i < n; i += 1) {
    sum += sorted[i];
    weightedSum += (i + 1) * sorted[i];
  }
  if (sum === 0) return 0;
  return (2 * weightedSum) / (n * sum) - (n + 1) / n;
}

export function runV5Simulation({
  houses = 100,
  days = 180,
  seed = 42,
  scenario = 'baseline',
} = {}) {
  if (!Number.isInteger(houses) || houses < 1) throw new Error('houses must be a positive integer');
  if (!Number.isInteger(days) || days < 1) throw new Error('days must be a positive integer');
  if (!V5_SCENARIOS.includes(scenario)) throw new Error(`Unknown V5 scenario: ${scenario}`);

  const random = rng(seed);
  const prices = { ...V5_BASE_PRICES };
  const priceHistory = Object.fromEntries(V5_RESOURCE_CODES.map((c) => [c, []]));
  const totals = {
    production: emptyResources(),
    consumption: emptyResources(),
    shortages: emptyResources(),
    marketTrades: 0,
    marketCreditVolume: 0,
    constructionCount: 0,
    tierUpgradeCount: 0,
    retrofitCount: 0,
    earthRevenue: 0,
    researchPoints: 0,
    scaleUnlocks: 0,
  };

  // Setup Corporations
  const numCorps = scenario === 'one-mega-corporation'
    ? 1
    : scenario === 'many-small-corporations'
      ? Math.max(10, Math.floor(houses / 10))
      : Math.max(2, Math.floor(houses / 50));

  const corporations = Array.from({ length: numCorps }, (_, i) => ({
    id: `CORP-${i + 1}`,
    name: `Corporation ${i + 1}`,
    treasury: 500_000 * (houses / 100),
    resources: emptyResources(100 * (houses / 100)),
    members: 0,
    publicBuildings: 0,
    scaleCapabilities: new Set(['SCALE_NONE']),
    researchProgress: 0,
    arrears: false,
    capacityRentPaid: 0,
    monopolist: scenario === 'corporation-material-monopoly' && i === 0,
  }));

  // Setup Houses
  const houseList = [];
  const independentFraction = scenario === 'independent-heavy' ? 0.85 : 0.15;
  const inactiveFraction = scenario === 'inactive-players' ? 0.40 : 0.05;

  for (let i = 0; i < houses; i += 1) {
    const isIndependent = random() < independentFraction;
    const corp = isIndependent ? null : corporations[Math.floor(random() * corporations.length)];
    if (corp) corp.members += 1;

    let specialization = 'balanced';
    if (scenario === 'all-houses-choose-energy') specialization = 'energy';
    else if (scenario === 'all-houses-choose-food') specialization = 'food';
    else if (scenario === 'corporation-material-monopoly' && corp?.monopolist) specialization = 'materials';
    else {
      const specs = ['materials', 'components', 'energy', 'compute', 'food', 'balanced'];
      specialization = specs[Math.floor(random() * specs.length)];
    }

    const isBankruptCandidate = scenario === 'bankrupt-producers' && i < Math.floor(houses * 0.2);

    houseList.push({
      id: `HOUSE-${i + 1}`,
      corpId: corp?.id ?? null,
      specialization,
      credits: isBankruptCandidate ? 500 : V5_STARTER.CREDIT,
      inventory: Object.fromEntries(
        V5_RESOURCE_CODES.map((c) => [c, isBankruptCandidate ? 1 : V5_STARTER[c]]),
      ),
      buildings: [
        { type: `${specialization.toUpperCase()}-T1`, tier: 1, generation: 1, active: true },
      ],
      active: random() >= inactiveFraction,
      solvent: true,
      arrearsDays: 0,
      occupiedSlots: 1,
      totalSlots: 10,
    });
  }

  // Daily Simulation Loop
  for (let day = 1; day <= days; day += 1) {
    let dayTrades = 0;
    let dayCreditVolume = 0;
    const marketBids = [];
    const marketAsks = [];

    // 1. Production and Life Maintenance
    for (const h of houseList) {
      if (!h.active || !h.solvent) continue;

      // Life Maintenance (Sink: 1 Food + 1 Energy per active house/day)
      const foodNeeded = 1;
      const energyNeeded = 1;

      if (h.inventory.FOOD >= foodNeeded) {
        h.inventory.FOOD -= foodNeeded;
        totals.consumption.FOOD += foodNeeded;
      } else {
        totals.shortages.FOOD += foodNeeded;
        h.arrearsDays += 1;
      }

      if (h.inventory.ENERGY >= energyNeeded) {
        h.inventory.ENERGY -= energyNeeded;
        totals.consumption.ENERGY += energyNeeded;
      } else {
        totals.shortages.ENERGY += energyNeeded;
        h.arrearsDays += 1;
      }

      if (h.arrearsDays > 14) {
        h.solvent = false; // Insolvency
      }

      // Building Production
      for (const b of h.buildings) {
        if (!b.active) continue;

        let inputMultiplier = 1;
        const specializationBonus = h.specialization !== 'balanced' ? 1.35 : 1.0;
        let outputMultiplier = 1 * specializationBonus;

        if (scenario === 'energy-shortage') {
          if (b.type.includes('ENERGY')) outputMultiplier = 0.4;
        } else if (scenario === 'compute-shortage') {
          if (b.type.includes('COMPUTE')) outputMultiplier = 0.3;
        } else if (scenario === 'excess-material') {
          if (b.type.includes('MATERIAL')) outputMultiplier = 2.5;
        } else if (scenario === 'excess-components') {
          if (b.type.includes('COMPONENT')) outputMultiplier = 2.5;
        }

        // Production flows
        let producedCode = 'MATERIAL';
        let producedAmount = 25 * b.tier * outputMultiplier;
        let consumedResource = 'ENERGY';
        let consumedAmount = 5 * b.tier * inputMultiplier;

        if (b.type.includes('ENERGY')) {
          producedCode = 'ENERGY';
          producedAmount = 30 * b.tier * outputMultiplier;
          consumedResource = 'MATERIAL';
          consumedAmount = 4 * b.tier * inputMultiplier;
        } else if (b.type.includes('FOOD')) {
          producedCode = 'FOOD';
          producedAmount = 20 * b.tier * outputMultiplier;
          consumedResource = 'ENERGY';
          consumedAmount = 3 * b.tier * inputMultiplier;
        } else if (b.type.includes('COMPONENT')) {
          producedCode = 'COMPONENTS';
          producedAmount = 15 * b.tier * outputMultiplier;
          consumedResource = 'MATERIAL';
          consumedAmount = 10 * b.tier * inputMultiplier;
        } else if (b.type.includes('COMPUTE')) {
          producedCode = 'COMPUTE';
          producedAmount = 12 * b.tier * outputMultiplier;
          consumedResource = 'ENERGY';
          consumedAmount = 8 * b.tier * inputMultiplier;
        }

        // Check if input resource available
        if (h.inventory[consumedResource] >= consumedAmount) {
          h.inventory[consumedResource] -= consumedAmount;
          h.inventory[producedCode] += producedAmount;
          totals.consumption[consumedResource] += consumedAmount;
          totals.production[producedCode] += producedAmount;
        } else {
          totals.shortages[consumedResource] += consumedAmount;
          // Partial production if starved
          const ratio = h.inventory[consumedResource] / consumedAmount;
          const actualConsumed = Math.floor(consumedAmount * ratio);
          const actualProduced = Math.floor(producedAmount * ratio);
          h.inventory[consumedResource] -= actualConsumed;
          h.inventory[producedCode] += actualProduced;
          totals.consumption[consumedResource] += actualConsumed;
          totals.production[producedCode] += actualProduced;
        }

        // Operating cost deduction
        const opCredit = V5_BUILDING_TIERS[b.tier]?.operatingCredit ?? 10;
        if (h.credits >= opCredit) {
          h.credits -= opCredit;
          totals.earthRevenue += opCredit;
        } else {
          h.arrearsDays += 1;
        }
      }

      // 2. Construction & Upgrades
      const canBuild = scenario !== 'stalled-construction';
      const isBoom = scenario === 'construction-boom';
      const buildProbability = isBoom ? 0.08 : 0.02;

      if (canBuild && h.active && random() < buildProbability && h.occupiedSlots < h.totalSlots) {
        const nextTier = 1;
        const tierConfig = V5_BUILDING_TIERS[nextTier];
        if (
          h.credits >= tierConfig.creditCost &&
          h.inventory.MATERIAL >= tierConfig.materialCost &&
          h.inventory.COMPONENTS >= tierConfig.componentCost
        ) {
          h.credits -= tierConfig.creditCost;
          h.inventory.MATERIAL -= tierConfig.materialCost;
          h.inventory.COMPONENTS -= tierConfig.componentCost;
          totals.consumption.MATERIAL += tierConfig.materialCost;
          totals.consumption.COMPONENTS += tierConfig.componentCost;
          totals.earthRevenue += tierConfig.creditCost;
          h.buildings.push({
            type: `${h.specialization.toUpperCase()}-T1`,
            tier: 1,
            generation: 1,
            active: true,
          });
          h.occupiedSlots += 1;
          totals.constructionCount += 1;
        }
      }

      // Tier Upgrade
      if (canBuild && h.active && random() < (isBoom ? 0.04 : 0.01)) {
        const b = h.buildings.find((item) => item.tier < 4);
        if (b) {
          const nextTier = b.tier + 1;
          const tierConfig = V5_BUILDING_TIERS[nextTier];
          if (
            h.credits >= tierConfig.creditCost &&
            h.inventory.MATERIAL >= tierConfig.materialCost &&
            h.inventory.COMPONENTS >= tierConfig.componentCost
          ) {
            h.credits -= tierConfig.creditCost;
            h.inventory.MATERIAL -= tierConfig.materialCost;
            h.inventory.COMPONENTS -= tierConfig.componentCost;
            totals.consumption.MATERIAL += tierConfig.materialCost;
            totals.consumption.COMPONENTS += tierConfig.componentCost;
            totals.earthRevenue += tierConfig.creditCost;
            b.tier = nextTier;
            totals.tierUpgradeCount += 1;
          }
        }
      }

      // Generate Market Orders
      for (const code of V5_RESOURCE_CODES) {
        const targetBuffer = code === 'FOOD' ? 15 : code === 'ENERGY' ? 25 : 10;
        const current = h.inventory[code];
        if (current < targetBuffer) {
          const buyQty = targetBuffer - current;
          marketBids.push({ house: h, code, quantity: buyQty, limitPrice: prices[code] * 1.05 });
        } else if (current > targetBuffer * 2) {
          const sellQty = Math.floor(current - targetBuffer * 1.5);
          marketAsks.push({ house: h, code, quantity: sellQty, limitPrice: prices[code] * 0.95 });
        }
      }
    }

    // 3. Corporation Actions & Research
    for (const corp of corporations) {
      // Corporation Capacity Rent
      const baseRentPerMember = scenario === 'low-rent'
        ? 5
        : scenario === 'progressive-rent'
          ? 20 + Math.floor(corp.members * 0.5)
          : 15;
      const totalRent = corp.members * baseRentPerMember;

      if (corp.treasury >= totalRent) {
        corp.treasury -= totalRent;
        corp.capacityRentPaid += totalRent;
        totals.earthRevenue += totalRent;
      } else {
        corp.arrears = true;
      }

      // Research Project funding
      const researchCost = 200 * Math.max(1, corp.members);
      if (corp.treasury >= researchCost && corp.resources.COMPUTE >= 2) {
        corp.treasury -= researchCost;
        corp.resources.COMPUTE -= 2;
        totals.consumption.COMPUTE += 2;
        totals.earthRevenue += researchCost;
        corp.researchProgress += 1;
        totals.researchPoints += 1;

        if (corp.researchProgress >= 50 && !corp.scaleCapabilities.has('SCALE_COMMERCIAL')) {
          corp.scaleCapabilities.add('SCALE_COMMERCIAL');
          totals.scaleUnlocks += 1;
        }
        if (corp.researchProgress >= 150 && !corp.scaleCapabilities.has('SCALE_INDUSTRIAL')) {
          corp.scaleCapabilities.add('SCALE_INDUSTRIAL');
          totals.scaleUnlocks += 1;
        }
      }
    }

    // 4. Batch Market Clearing
    for (const code of V5_RESOURCE_CODES) {
      const bids = marketBids.filter((b) => b.code === code);
      const asks = marketAsks.filter((a) => a.code === code);

      const totalDemand = bids.reduce((sum, b) => sum + b.quantity, 0);
      const totalSupply = asks.reduce((sum, a) => sum + a.quantity, 0);

      const cleared = Math.min(totalDemand, totalSupply);
      if (cleared > 0) {
        const tradeCredit = cleared * prices[code];
        dayTrades += bids.length + asks.length;
        dayCreditVolume += tradeCredit;

        // Balance supply/demand distribution
        let remainingToClear = cleared;
        for (const bid of bids) {
          const allocated = Math.min(bid.quantity, Math.floor(cleared * (bid.quantity / totalDemand)));
          if (bid.house.credits >= allocated * prices[code]) {
            bid.house.credits -= allocated * prices[code];
            bid.house.inventory[code] += allocated;
          }
        }
        for (const ask of asks) {
          const sold = Math.min(ask.quantity, Math.floor(cleared * (ask.quantity / totalSupply)));
          ask.house.inventory[code] -= sold;
          ask.house.credits += sold * prices[code];
        }
      }

      // Elastic price update with mean reversion bounds
      const pressure = (totalSupply + 1) / (totalDemand + 1);
      const delta = (1 - pressure) * 0.04 + (random() - 0.5) * 0.01;
      prices[code] = Math.max(5, Math.min(5000, prices[code] * (1 + Math.max(-0.06, Math.min(0.06, delta)))));
      priceHistory[code].push(prices[code]);
    }

    totals.marketTrades += dayTrades;
    totals.marketCreditVolume += dayCreditVolume;
  }

  // Aggregate Final Statistics
  const solventHouses = houseList.filter((h) => h.solvent);
  const solventCorps = corporations.filter((c) => !c.arrears);
  const houseWealths = houseList.map((h) =>
    h.credits + V5_RESOURCE_CODES.reduce((sum, c) => sum + h.inventory[c] * prices[c], 0),
  );
  const meanWealth = houseWealths.reduce((sum, w) => sum + w, 0) / Math.max(1, houseWealths.length);
  const maxWealth = Math.max(...houseWealths, 0);
  const gini = calculateGini(houseWealths);

  const specializedWealth = houseList
    .filter((h) => h.specialization !== 'balanced')
    .map((h) => h.credits + V5_RESOURCE_CODES.reduce((sum, c) => sum + h.inventory[c] * prices[c], 0));
  const autarkyWealth = houseList
    .filter((h) => h.specialization === 'balanced')
    .map((h) => h.credits + V5_RESOURCE_CODES.reduce((sum, c) => sum + h.inventory[c] * prices[c], 0));

  const meanSpecialized = specializedWealth.length
    ? specializedWealth.reduce((s, w) => s + w, 0) / specializedWealth.length
    : meanWealth;
  const meanAutarky = autarkyWealth.length
    ? autarkyWealth.reduce((s, w) => s + w, 0) / autarkyWealth.length
    : meanWealth;

  const closingInventories = emptyResources();
  for (const h of houseList) {
    for (const c of V5_RESOURCE_CODES) closingInventories[c] += h.inventory[c];
  }

  const averagePrices = Object.fromEntries(
    V5_RESOURCE_CODES.map((c) => [
      c,
      priceHistory[c].reduce((sum, p) => sum + p, 0) / Math.max(1, priceHistory[c].length),
    ]),
  );

  const territoryOccupiedSlots = houseList.reduce((sum, h) => sum + h.occupiedSlots, 0);
  const territoryTotalCapacity = houseList.reduce((sum, h) => sum + h.totalSlots, 0);

  return {
    scenario,
    houses,
    days,
    seed,
    survivingHouses: solventHouses.length,
    survivalRate: solventHouses.length / houses,
    production: totals.production,
    consumption: totals.consumption,
    shortages: totals.shortages,
    inventories: closingInventories,
    openingPrices: V5_BASE_PRICES,
    closingPrices: prices,
    averagePrices,
    marketVolume: {
      trades: totals.marketTrades,
      creditVolume: totals.marketCreditVolume,
    },
    houseSolvency: {
      solvent: solventHouses.length,
      insolvent: houses - solventHouses.length,
      solvencyRate: solventHouses.length / houses,
    },
    corporationSolvency: {
      total: corporations.length,
      solvent: solventCorps.length,
      insolvent: corporations.length - solventCorps.length,
      averageTreasury: corporations.reduce((s, c) => s + c.treasury, 0) / Math.max(1, corporations.length),
    },
    earthRevenue: totals.earthRevenue,
    constructionFrequency: {
      newBuildings: totals.constructionCount,
      tierUpgrades: totals.tierUpgradeCount,
      retrofits: totals.retrofitCount,
    },
    technologyPace: {
      researchPoints: totals.researchPoints,
      scaleUnlocks: totals.scaleUnlocks,
    },
    territoryUtilization: {
      occupiedSlots: territoryOccupiedSlots,
      totalCapacity: territoryTotalCapacity,
      utilizationRate: territoryOccupiedSlots / Math.max(1, territoryTotalCapacity),
    },
    concentration: {
      gini,
      meanWealth,
      maxWealth,
      maxToMean: maxWealth / Math.max(1, meanWealth),
    },
    specializationComparison: {
      meanSpecializedWealth: meanSpecialized,
      meanAutarkyWealth: meanAutarky,
      specializationAdvantageRatio: meanSpecialized / Math.max(1, meanAutarky),
    },
  };
}
