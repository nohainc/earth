import type { PostgresRepository } from './repository.ts';

export async function resolveEconomicAccount(repository: PostgresRepository, principalId: string, accountPurpose: string, asset = 'CREDIT'): Promise<string> {
  const result = await repository.query<{ account_id: string }>(
    `SELECT a.id::TEXT AS account_id FROM economic_accounts a
       JOIN owner_registry o ON o.economic_id=a.owner_economic_id
       JOIN economic_assets asset ON asset.id=a.asset_id
      WHERE (o.id=$1 OR o.economic_id=$1) AND a.account_type=$2 AND asset.code=$3 AND a.status='ACTIVE'
      ORDER BY a.id LIMIT 1`, [principalId, accountPurpose, asset.toUpperCase()]);
  if (!result.rows[0]) throw new Error(`Active ${accountPurpose}/${asset} account not found for principal ${principalId}`);
  return result.rows[0].account_id;
}
