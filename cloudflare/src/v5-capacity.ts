/** Pure V5 pooled capacity calculations. */

import { calculateProgressiveCharge, type ProgressiveBracket, type ProgressiveCharge } from './v5-progressive.ts';

export type CapacityBuilding = {
  id: string;
  footprint: bigint;
  billable: boolean;
};

export type HouseCapacity = {
  houseId: string;
  corporationId: string | null;
  residentialUnits: bigint;
  buildingUnits: bigint;
  totalUnits: bigint;
};

export type CorporationCapacity = {
  corporationId: string;
  memberCount: bigint;
  residentialUnits: bigint;
  privateBuildingUnits: bigint;
  publicBuildingUnits: bigint;
  totalOccupiedUnits: bigint;
  standardTerritoryCapacity: bigint;
  requiredTerritoryUnits: bigint;
  utilizationNumerator: bigint;
  utilizationDenominator: bigint;
};

function nonNegative(value: bigint, label: string): bigint {
  if (value < 0n) throw new Error(`${label} must be non-negative`);
  return value;
}

export function calculateHouseCapacity(input: {
  houseId: string;
  corporationId?: string | null;
  activeAffiliation: boolean;
  buildings: readonly CapacityBuilding[];
}): HouseCapacity {
  const buildingUnits = input.buildings.reduce((sum, building) => {
    if (!building.billable) return sum;
    return sum + nonNegative(building.footprint, 'Building footprint');
  }, 0n);
  // Residential occupancy belongs to the House, not its Corporation
  // affiliation. Keep the legacy argument in the input shape for compatibility
  // while ensuring it cannot erase protected residential capacity.
  void input.activeAffiliation;
  const residentialUnits = 1n;
  return { houseId: input.houseId, corporationId: input.corporationId ?? null, residentialUnits, buildingUnits, totalUnits: residentialUnits + buildingUnits };
}

export function requiredTerritoryUnits(occupiedUnits: bigint, standardCapacity: bigint): bigint {
  nonNegative(occupiedUnits, 'Occupied capacity');
  if (standardCapacity <= 0n) throw new Error('Standard Territory capacity must be positive');
  return occupiedUnits === 0n ? 0n : (occupiedUnits + standardCapacity - 1n) / standardCapacity;
}

export function aggregateCorporationCapacity(input: {
  corporationId: string;
  houses: readonly HouseCapacity[];
  publicBuildingUnits?: bigint;
  standardTerritoryCapacity: bigint;
}): CorporationCapacity {
  const publicBuildingUnits = nonNegative(input.publicBuildingUnits ?? 0n, 'Public building units');
  const members = input.houses.filter((house) => house.corporationId === input.corporationId);
  const residentialUnits = members.reduce((sum, house) => sum + house.residentialUnits, 0n);
  const privateBuildingUnits = members.reduce((sum, house) => sum + house.buildingUnits, 0n);
  const totalOccupiedUnits = residentialUnits + privateBuildingUnits + publicBuildingUnits;
  return {
    corporationId: input.corporationId,
    memberCount: BigInt(members.filter((house) => house.residentialUnits === 1n).length),
    residentialUnits,
    privateBuildingUnits,
    publicBuildingUnits,
    totalOccupiedUnits,
    standardTerritoryCapacity: input.standardTerritoryCapacity,
    requiredTerritoryUnits: requiredTerritoryUnits(totalOccupiedUnits, input.standardTerritoryCapacity),
    utilizationNumerator: totalOccupiedUnits,
    utilizationDenominator: input.standardTerritoryCapacity * requiredTerritoryUnits(totalOccupiedUnits, input.standardTerritoryCapacity),
  };
}

export type CapacityQuote = {
  currentUsage: bigint;
  delta: bigint;
  afterUsage: bigint;
  currentCharge: ProgressiveCharge;
  afterCharge: ProgressiveCharge;
  incrementalCharge: bigint;
};

/** Shared preview primitive for capacity-changing commands and settlement. */
export function quoteCapacityChange(input: {
  currentUsage: bigint;
  delta: bigint;
  baseRate: bigint;
  brackets: readonly ProgressiveBracket[];
}): CapacityQuote {
  nonNegative(input.currentUsage, 'Current usage');
  if (input.delta < 0n && -input.delta > input.currentUsage) throw new Error('Capacity cannot become negative');
  const afterUsage = input.currentUsage + input.delta;
  const currentCharge = calculateProgressiveCharge({ quantity: input.currentUsage, baseRate: input.baseRate, brackets: input.brackets });
  const afterCharge = calculateProgressiveCharge({ quantity: afterUsage, baseRate: input.baseRate, brackets: input.brackets });
  return { currentUsage: input.currentUsage, delta: input.delta, afterUsage, currentCharge, afterCharge, incrementalCharge: afterCharge.totalCharge - currentCharge.totalCharge };
}
