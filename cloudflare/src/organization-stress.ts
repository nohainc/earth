export type OrganizationHealthInput = { liquidUnits: bigint; assetsUnits: bigint; liabilitiesUnits: bigint; overdueUnits: bigint };

export function evaluateOrganizationHealth(input: OrganizationHealthInput): 'HEALTHY' | 'WATCH' | 'STRESS' | 'INSOLVENT' {
  if ([input.liquidUnits, input.assetsUnits, input.liabilitiesUnits, input.overdueUnits].some((value) => value < 0n)) throw new Error('Organization financial facts cannot be negative');
  if (input.liabilitiesUnits === 0n || input.liquidUnits >= input.liabilitiesUnits) return 'HEALTHY';
  if (input.liquidUnits * 2n >= input.liabilitiesUnits && input.overdueUnits === 0n) return 'WATCH';
  if (input.liquidUnits > 0n && input.assetsUnits >= input.liabilitiesUnits) return 'STRESS';
  return 'INSOLVENT';
}
