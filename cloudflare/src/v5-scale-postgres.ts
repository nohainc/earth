import type { PostgresRepository } from './repository.ts';

// @mutation-boundary caller-owned-transaction

export type ScaleCapability = 'SCALE_NONE' | 'SCALE_COMMERCIAL' | 'SCALE_INDUSTRIAL' | 'SCALE_STRATEGIC';

export async function getAvailableScaleCapabilities(
  tx: PostgresRepository,
  ownerEconomicId: string,
  ownerType: 'HOUSE' | 'CORPORATION',
  affiliatedCorpEconomicId?: string | null,
): Promise<Set<string>> {
  const capabilities = new Set<string>(['SCALE_NONE']);

  // 1. Earth public-domain baseline scale capabilities are available to all
  const earthCaps = await tx.query<{ scale_capability: string }>(
    'SELECT scale_capability FROM earth_scale_capabilities',
  );
  for (const row of earthCaps.rows) {
    capabilities.add(row.scale_capability);
  }

  // 2. Corporation-specific scale capabilities
  const targetCorpEconId = ownerType === 'CORPORATION' ? ownerEconomicId : affiliatedCorpEconomicId;
  if (targetCorpEconId) {
    const corpCaps = await tx.query<{ scale_capability: string }>(
      'SELECT scale_capability FROM corporation_scale_capabilities WHERE corporation_economic_id = $1',
      [targetCorpEconId],
    );
    for (const row of corpCaps.rows) {
      capabilities.add(row.scale_capability);
    }
  }

  return capabilities;
}

export async function assertScaleCapabilityAuthorized(
  tx: PostgresRepository,
  minimumScaleCapability: string,
  ownerEconomicId: string,
  ownerType: 'HOUSE' | 'CORPORATION',
  affiliatedCorpEconomicId?: string | null,
): Promise<{ authorized: boolean; reason?: string }> {
  if (!minimumScaleCapability || minimumScaleCapability === 'SCALE_NONE') {
    return { authorized: true };
  }

  const available = await getAvailableScaleCapabilities(tx, ownerEconomicId, ownerType, affiliatedCorpEconomicId);
  if (available.has(minimumScaleCapability)) {
    return { authorized: true };
  }

  return {
    authorized: false,
    reason: `Missing required scale capability: ${minimumScaleCapability}`,
  };
}

export async function grantCorporationScaleCapability(
  tx: PostgresRepository,
  corpEconomicId: string,
  capability: ScaleCapability,
  gameDay = 1,
): Promise<void> {
  if (capability === 'SCALE_NONE') return;
  await tx.query(
    `INSERT INTO corporation_scale_capabilities (corporation_economic_id, scale_capability, unlocked_game_day)
     VALUES ($1, $2, $3)
     ON CONFLICT (corporation_economic_id, scale_capability) DO NOTHING`,
    [corpEconomicId, capability, gameDay],
  );
}

export async function grantEarthBaselineScaleCapability(
  tx: PostgresRepository,
  capability: ScaleCapability,
  gameDay = 1,
): Promise<void> {
  if (capability === 'SCALE_NONE') return;
  await tx.query(
    `INSERT INTO earth_scale_capabilities (scale_capability, unlocked_game_day)
     VALUES ($1, $2)
     ON CONFLICT (scale_capability) DO NOTHING`,
    [capability, gameDay],
  );
}
