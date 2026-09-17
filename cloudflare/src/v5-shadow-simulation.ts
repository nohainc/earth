import { calculateProgressiveCharge, type ProgressiveBracket } from './v5-progressive.ts';

/**
 * Deterministic V5 balancing harness. This is deliberately isolated from the
 * Worker request path and never writes production state.
 */
export type V5ShadowHouse = {
  id: string;
  corporationId: string;
  occupiedUnits: bigint;
  startingWalletUnits: bigint;
  dailyIncomeUnits: bigint;
  active: boolean;
};

export type V5ShadowCorporation = {
  id: string;
  startingWalletUnits: bigint;
  dailyIncomeUnits: bigint;
};

export type V5ShadowPolicy = {
  standardTerritoryCapacityUnits: bigint;
  earthBaseRateUnits: bigint;
  earthBrackets: ProgressiveBracket[];
  houseBaseRateByCorporation: Readonly<Record<string, bigint>>;
  houseBrackets: ProgressiveBracket[];
};

export type V5ShadowDay = {
  gameDay: number;
  occupiedUnits: bigint;
  requiredTerritoryUnits: bigint;
  houseAssessedUnits: bigint;
  housePaidUnits: bigint;
  earthAssessedUnits: bigint;
  earthPaidUnits: bigint;
  houseArrearsCount: number;
  corporationArrearsCount: number;
  corporationWallets: Readonly<Record<string, bigint>>;
};

export type V5ShadowResult = {
  days: readonly V5ShadowDay[];
  finalHouseWallets: Readonly<Record<string, bigint>>;
  finalCorporationWallets: Readonly<Record<string, bigint>>;
  totalHouseArrearsUnits: bigint;
  totalEarthArrearsUnits: bigint;
  peakRequiredTerritoryUnits: bigint;
  metrics: {
    houseSurvivalRateBps: bigint;
    houseWealthMinimumUnits: bigint;
    houseWealthMaximumUnits: bigint;
    houseWealthAverageUnits: bigint;
    corporationConcentrationBps: bigint;
    averageCapacityUtilizationBps: bigint;
    totalEarthRevenueUnits: bigint;
  };
};

function requirePositive(value: bigint, field: string): void {
  if (value <= 0n) throw new Error(`${field} must be positive`);
}

/** Run a fixed number of daily settlement observations using exact units. */
export function runV5ShadowSimulation(input: {
  days: number;
  houses: readonly V5ShadowHouse[];
  corporations: readonly V5ShadowCorporation[];
  policy: V5ShadowPolicy;
}): V5ShadowResult {
  if (!Number.isInteger(input.days) || input.days < 1 || input.days > 3650) {
    throw new Error('Simulation days must be an integer between 1 and 3650');
  }
  requirePositive(input.policy.standardTerritoryCapacityUnits, 'Standard Territory capacity');
  if (new Set(input.houses.map((house) => house.id)).size !== input.houses.length) {
    throw new Error('House IDs must be unique');
  }
  const corporationIds = new Set(input.corporations.map((corporation) => corporation.id));
  if (corporationIds.size !== input.corporations.length) throw new Error('Corporation IDs must be unique');
  for (const house of input.houses) {
    if (!corporationIds.has(house.corporationId)) throw new Error(`Unknown Corporation for House ${house.id}`);
    if (house.occupiedUnits < 0n || house.startingWalletUnits < 0n || house.dailyIncomeUnits < 0n) {
      throw new Error(`Negative House simulation input: ${house.id}`);
    }
  }

  const houseWallets = new Map(input.houses.map((house) => [house.id, house.startingWalletUnits]));
  const corporationWallets = new Map(input.corporations.map((corporation) => [corporation.id, corporation.startingWalletUnits]));
  const days: V5ShadowDay[] = [];
  let totalHouseArrearsUnits = 0n;
  let totalEarthArrearsUnits = 0n;
  let peakRequiredTerritoryUnits = 0n;
  let totalCapacityUtilizationBps = 0n;
  let totalEarthRevenueUnits = 0n;

  for (let gameDay = 1; gameDay <= input.days; gameDay += 1) {
    for (const house of input.houses) {
      if (house.active) houseWallets.set(house.id, (houseWallets.get(house.id) ?? 0n) + house.dailyIncomeUnits);
    }
    for (const corporation of input.corporations) {
      corporationWallets.set(corporation.id, (corporationWallets.get(corporation.id) ?? 0n) + corporation.dailyIncomeUnits);
    }

    let occupiedUnits = 0n;
    let houseAssessedUnits = 0n;
    let housePaidUnits = 0n;
    let houseArrearsCount = 0;
    const corporationUsage = new Map<string, bigint>();
    for (const house of input.houses) {
      if (!house.active) continue;
      occupiedUnits += house.occupiedUnits;
      corporationUsage.set(house.corporationId, (corporationUsage.get(house.corporationId) ?? 0n) + house.occupiedUnits);
      const baseRate = input.policy.houseBaseRateByCorporation[house.corporationId];
      if (baseRate == null) throw new Error(`Missing House capacity rate for ${house.corporationId}`);
      const assessed = calculateProgressiveCharge({ quantity: house.occupiedUnits, baseRate, brackets: input.policy.houseBrackets }).totalCharge;
      const wallet = houseWallets.get(house.id) ?? 0n;
      const paid = wallet < assessed ? wallet : assessed;
      houseWallets.set(house.id, wallet - paid);
      const corporationWallet = corporationWallets.get(house.corporationId) ?? 0n;
      corporationWallets.set(house.corporationId, corporationWallet + paid);
      houseAssessedUnits += assessed;
      housePaidUnits += paid;
      if (paid < assessed) {
        houseArrearsCount += 1;
        totalHouseArrearsUnits += assessed - paid;
      }
    }

    let earthAssessedUnits = 0n;
    let earthPaidUnits = 0n;
    let corporationArrearsCount = 0;
    for (const corporation of input.corporations) {
      const usage = corporationUsage.get(corporation.id) ?? 0n;
      const assessed = calculateProgressiveCharge({ quantity: usage, baseRate: input.policy.earthBaseRateUnits, brackets: input.policy.earthBrackets }).totalCharge;
      const wallet = corporationWallets.get(corporation.id) ?? 0n;
      const paid = wallet < assessed ? wallet : assessed;
      corporationWallets.set(corporation.id, wallet - paid);
      earthAssessedUnits += assessed;
      earthPaidUnits += paid;
      if (paid < assessed) {
        corporationArrearsCount += 1;
        totalEarthArrearsUnits += assessed - paid;
      }
    }
    const requiredTerritoryUnits = occupiedUnits === 0n ? 0n :
        (occupiedUnits + input.policy.standardTerritoryCapacityUnits - 1n) /
            input.policy.standardTerritoryCapacityUnits;
    if (requiredTerritoryUnits > peakRequiredTerritoryUnits) peakRequiredTerritoryUnits = requiredTerritoryUnits;
    const capacityDenominator = requiredTerritoryUnits * input.policy.standardTerritoryCapacityUnits;
    totalCapacityUtilizationBps += capacityDenominator === 0n
      ? 0n
      : (occupiedUnits * 10_000n) / capacityDenominator;
    totalEarthRevenueUnits += earthPaidUnits;
    days.push({
      gameDay,
      occupiedUnits,
      requiredTerritoryUnits,
      houseAssessedUnits,
      housePaidUnits,
      earthAssessedUnits,
      earthPaidUnits,
      houseArrearsCount,
      corporationArrearsCount,
      corporationWallets: Object.fromEntries(corporationWallets),
    });
  }

  const finalHouseWalletValues = [...houseWallets.values()];
  const totalOccupiedByCorporation = [...new Map(input.houses.map((house) => [house.corporationId, 0n])).keys()]
    .map((corporationId) => input.houses.filter((house) => house.active && house.corporationId === corporationId)
      .reduce((sum, house) => sum + house.occupiedUnits, 0n));
  const totalOccupied = totalOccupiedByCorporation.reduce((sum, value) => sum + value, 0n);
  const largestCorporationOccupied = totalOccupiedByCorporation.reduce((largest, value) => value > largest ? value : largest, 0n);
  return {
    days,
    finalHouseWallets: Object.fromEntries(houseWallets),
    finalCorporationWallets: Object.fromEntries(corporationWallets),
    totalHouseArrearsUnits,
    totalEarthArrearsUnits,
    peakRequiredTerritoryUnits,
    metrics: {
      houseSurvivalRateBps: input.houses.length === 0 ? 10_000n : (BigInt(input.houses.filter((house) => house.active).length) * 10_000n) / BigInt(input.houses.length),
      houseWealthMinimumUnits: finalHouseWalletValues.length === 0 ? 0n : finalHouseWalletValues.reduce((minimum, value) => value < minimum ? value : minimum, finalHouseWalletValues[0]),
      houseWealthMaximumUnits: finalHouseWalletValues.reduce((maximum, value) => value > maximum ? value : maximum, 0n),
      houseWealthAverageUnits: finalHouseWalletValues.length === 0 ? 0n : finalHouseWalletValues.reduce((sum, value) => sum + value, 0n) / BigInt(finalHouseWalletValues.length),
      corporationConcentrationBps: totalOccupied === 0n ? 0n : (largestCorporationOccupied * 10_000n) / totalOccupied,
      averageCapacityUtilizationBps: input.days === 0 ? 0n : totalCapacityUtilizationBps / BigInt(input.days),
      totalEarthRevenueUnits,
    },
  };
}
