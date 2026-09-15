export type NexusType = 'RESIDENCE' | 'ASSET_LOCATION' | 'MEMBERSHIP' | 'TRANSACTION' | 'EARTH';

export function resolveNexus(input: { nexusType: NexusType; residenceTerritoryId: string | null; assetTerritoryId?: string | null; membershipTerritoryId?: string | null; transactionTerritoryId?: string | null }): string | null {
  if (input.nexusType === 'RESIDENCE') return input.residenceTerritoryId;
  if (input.nexusType === 'ASSET_LOCATION') return input.assetTerritoryId ?? null;
  if (input.nexusType === 'MEMBERSHIP') return input.membershipTerritoryId ?? null;
  if (input.nexusType === 'TRANSACTION') return input.transactionTerritoryId ?? null;
  return 'EARTH';
}
