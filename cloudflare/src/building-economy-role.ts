export type BuildingEconomicRole = 'PRODUCER' | 'TRANSFORMER' | 'SERVICE' | 'INFRASTRUCTURE' | 'ESTATE';

export type BuildingRoleFacts = {
  ownershipScope: 'PRIVATE' | 'PUBLIC';
  serviceType?: string | null;
  serviceCapacityUnits?: bigint | number | string | null;
  inputUnits?: Record<string, unknown> | string | null;
  outputUnits?: Record<string, unknown> | string | null;
};

function hasPositiveEntries(value: Record<string, unknown> | string | null | undefined): boolean {
  if (value == null) return false;
  const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : value;
  return Object.values(parsed).some((amount) => {
    try { return BigInt(String(amount)) > 0n; } catch { return false; }
  });
}

function hasPositiveCapacity(value: bigint | number | string | null | undefined): boolean {
  if (value == null) return false;
  try { return BigInt(String(value)) > 0n; } catch { return false; }
}

/** One stable role drives catalog filters, settlement routing, and UI explanation. */
export function classifyBuildingEconomicRole(facts: BuildingRoleFacts): BuildingEconomicRole {
  if (facts.ownershipScope === 'PUBLIC') return 'INFRASTRUCTURE';
  if (facts.serviceType?.trim() && hasPositiveCapacity(facts.serviceCapacityUnits)) return 'SERVICE';
  const input = hasPositiveEntries(facts.inputUnits);
  const output = hasPositiveEntries(facts.outputUnits);
  if (input && output) return 'TRANSFORMER';
  if (output) return 'PRODUCER';
  return 'ESTATE';
}
