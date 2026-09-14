import type { PostgresRepository } from './repository.ts';

export type ResourceKind = 'MATERIAL' | 'COMPONENTS' | 'ENERGY' | 'COMPUTE' | 'FOOD';
export type ResourceLedgerRow = { id: string; game_day: string | number; game_minute: number; owner_id: string; resource: ResourceKind; delta: string | number; balance_after: string | number; reason_type: string; reason_id: string | null; correlation_id: string | null; created_at: string };
export type ResourceDailyAggregate = { game_day: number; resource: ResourceKind; total_inflow: number; total_outflow: number; net_change: number; ending_balance?: number };

/** Read-only ledger history. Resource mutations use canonical settlement transactions. */
export async function getResourceLedgerHistory(repository: PostgresRepository, ownerId: string, options?: { resource?: ResourceKind; limit?: number; offset?: number }): Promise<ResourceLedgerRow[]> {
  const limit = Math.min(100, Math.max(1, options?.limit ?? 50));
  const offset = Math.max(0, options?.offset ?? 0);
  const result = await repository.query<ResourceLedgerRow>(
    `SELECT e.id::TEXT id,t.game_day,t.game_minute,a.owner_economic_id owner_id,asset.code resource,e.delta_units delta,a.balance_units balance_after,t.transaction_kind reason_type,t.source_id reason_id,t.correlation_id,t.created_at
       FROM economic_entries e JOIN economic_transactions t ON t.id=e.transaction_id JOIN economic_accounts a ON a.id=e.account_id JOIN economic_assets asset ON asset.id=e.asset_id
      WHERE a.owner_economic_id=$1 AND asset.asset_kind='RESOURCE' AND ($2::TEXT IS NULL OR asset.code=$2)
      ORDER BY t.game_day DESC,t.created_at DESC LIMIT $3 OFFSET $4`, [ownerId, options?.resource ?? null, limit, offset]);
  return result.rows;
}

export async function getResourceDailyBreakdown(repository: PostgresRepository, ownerId: string, days = 14): Promise<Record<string, ResourceDailyAggregate[]>> {
  const result = await repository.query<{ game_day: string | number; resource: ResourceKind; total_inflow: string; total_outflow: string; net_change: string; ending_balance: string }>(
    `SELECT t.game_day,asset.code resource,COALESCE(SUM(e.delta_units) FILTER (WHERE e.delta_units>0),0)::TEXT total_inflow,COALESCE(SUM(ABS(e.delta_units)) FILTER (WHERE e.delta_units<0),0)::TEXT total_outflow,COALESCE(SUM(e.delta_units),0)::TEXT net_change,COALESCE(MAX(a.balance_units),0)::TEXT ending_balance
       FROM economic_entries e JOIN economic_transactions t ON t.id=e.transaction_id JOIN economic_accounts a ON a.id=e.account_id JOIN economic_assets asset ON asset.id=e.asset_id
      WHERE a.owner_economic_id=$1 AND asset.asset_kind='RESOURCE' GROUP BY t.game_day,asset.code ORDER BY t.game_day DESC LIMIT $2`, [ownerId, Math.max(1, days) * 5]);
  const output: Record<string, ResourceDailyAggregate[]> = {};
  for (const row of result.rows) (output[row.resource] ??= []).push({ game_day: Number(row.game_day), resource: row.resource, total_inflow: Number(row.total_inflow), total_outflow: Number(row.total_outflow), net_change: Number(row.net_change), ending_balance: Number(row.ending_balance) });
  return output;
}
