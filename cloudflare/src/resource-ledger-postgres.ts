import type { PostgresRepository } from './repository.ts';

export type ResourceKind = 'material' | 'components' | 'energy' | 'compute' | 'food';
export type ExtendedResourceKind = ResourceKind | 'credits';

export type ResourceLedgerRow = {
  id: string;
  game_day: string | number;
  game_minute: number;
  owner_id: string;
  resource: ResourceKind;
  delta: string | number;
  balance_after: string | number;
  reason_type: string;
  reason_id: string | null;
  correlation_id: string | null;
  created_at: string;
};

export type ResourceRateHistoryRow = {
  id: string;
  owner_id: string;
  game_day: string | number;
  game_minute: number;
  created_at: string;
  trigger_event: string;
  trigger_entity_id: string | null;
  resource: ExtendedResourceKind;
  gross_inflow: string | number;
  gross_outflow: string | number;
  tax_amount: string | number;
  net_daily_rate: string | number;
};

export type ResourceDailyAggregate = {
  game_day: number;
  resource: ResourceKind;
  total_inflow: number;
  total_outflow: number;
  net_change: number;
  ending_balance?: number;
};

export type MutateResourceInput = {
  ownerId: string;
  resource: ResourceKind;
  delta: number;
  reasonType: string;
  reasonId?: string | null;
  correlationId?: string | null;
  gameDay?: number | null;
  gameMinute?: number;
};

export type MutateResourceResult = {
  status: 'success' | 'already_processed';
  ledgerId: string;
  ownerId: string;
  resource: string;
  delta: number;
  balanceAfter: number;
  alreadyProcessed: boolean;
};

/**
 * Authoritatively executes an atomic resource balance change in PostgreSQL.
 */
export async function mutateResourceBalance(
  repository: PostgresRepository,
  input: MutateResourceInput,
): Promise<MutateResourceResult> {
  const result = await repository.query<{
    status: string;
    ledger_id: string;
    owner_id: string;
    resource: string;
    delta: string | number;
    balance_after: string | number;
    already_processed: boolean;
  }>(
    'SELECT * FROM earth_mutate_resource_balance($1, $2, $3, $4, $5, $6, $7, $8)',
    [
      input.gameDay ?? null,
      input.ownerId,
      input.resource,
      input.delta,
      input.reasonType,
      input.reasonId ?? null,
      input.correlationId ?? null,
      input.gameMinute ?? 0,
    ],
  );

  const row = result.rows[0];
  if (!row) {
    throw new Error('Resource mutation failed: no response from database function');
  }

  return {
    status: row.status as 'success' | 'already_processed',
    ledgerId: row.ledger_id,
    ownerId: row.owner_id,
    resource: row.resource,
    delta: Number(row.delta),
    balanceAfter: Number(row.balance_after),
    alreadyProcessed: Boolean(row.already_processed),
  };
}

/**
 * Records a timestamped rate change snapshot across all 6 resources.
 */
export async function recordRateChange(
  repository: PostgresRepository,
  ownerId: string,
  triggerEvent: string,
  triggerEntityId?: string | null,
  gameDay?: number | null,
  gameMinute?: number | null,
): Promise<ResourceRateHistoryRow[]> {
  const res = await repository.query<ResourceRateHistoryRow>(
    'SELECT * FROM earth_record_rate_change($1, $2, $3, $4, $5)',
    [ownerId, triggerEvent, triggerEntityId ?? null, gameDay ?? null, gameMinute ?? null],
  );
  return res.rows;
}

/**
 * Fetches recent resource ledger history for an entity.
 */
export async function getResourceLedgerHistory(
  repository: PostgresRepository,
  ownerId: string,
  options?: { resource?: ResourceKind; limit?: number; offset?: number },
): Promise<ResourceLedgerRow[]> {
  const limit = Math.min(100, Math.max(1, options?.limit ?? 50));
  const offset = Math.max(0, options?.offset ?? 0);

  if (options?.resource) {
    const res = await repository.query<ResourceLedgerRow>(
      `SELECT * FROM resource_ledger_entries
       WHERE owner_id = $1 AND resource = $2
       ORDER BY game_day DESC, created_at DESC
       LIMIT $3 OFFSET $4`,
      [ownerId, options.resource, limit, offset],
    );
    return res.rows;
  }

  const res = await repository.query<ResourceLedgerRow>(
    `SELECT * FROM resource_ledger_entries
     WHERE owner_id = $1
     ORDER BY game_day DESC, created_at DESC
     LIMIT $2 OFFSET $3`,
    [ownerId, limit, offset],
  );
  return res.rows;
}

/**
 * Fetches timestamped rate change history for an entity.
 */
export async function getResourceRateHistory(
  repository: PostgresRepository,
  ownerId: string,
  options?: { resource?: ExtendedResourceKind; limit?: number; offset?: number },
): Promise<ResourceRateHistoryRow[]> {
  const limit = Math.min(100, Math.max(1, options?.limit ?? 50));
  const offset = Math.max(0, options?.offset ?? 0);

  if (options?.resource) {
    const res = await repository.query<ResourceRateHistoryRow>(
      `SELECT * FROM resource_rate_history
       WHERE owner_id = $1 AND resource = $2
       ORDER BY game_day DESC, created_at DESC
       LIMIT $3 OFFSET $4`,
      [ownerId, options.resource, limit, offset],
    );
    return res.rows;
  }

  const res = await repository.query<ResourceRateHistoryRow>(
    `SELECT * FROM resource_rate_history
     WHERE owner_id = $1
     ORDER BY game_day DESC, created_at DESC
     LIMIT $2 OFFSET $3`,
    [ownerId, limit, offset],
  );
  return res.rows;
}

/**
 * Aggregates daily resource flows (inflow, outflow, net) for historical charts.
 */
export async function getResourceDailyBreakdown(
  repository: PostgresRepository,
  ownerId: string,
  days = 14,
): Promise<Record<string, ResourceDailyAggregate[]>> {
  const result = await repository.query<{
    game_day: string | number;
    resource: ResourceKind;
    total_inflow: string | number;
    total_outflow: string | number;
    net_change: string | number;
  }>(
    `SELECT
       game_day,
       resource,
       COALESCE(SUM(CASE WHEN delta > 0 THEN delta ELSE 0 END), 0) AS total_inflow,
       COALESCE(SUM(CASE WHEN delta < 0 THEN ABS(delta) ELSE 0 END), 0) AS total_outflow,
       COALESCE(SUM(delta), 0) AS net_change
     FROM resource_ledger_entries
     WHERE owner_id = $1
     GROUP BY game_day, resource
     ORDER BY game_day DESC
     LIMIT $2`,
    [ownerId, days * 5],
  );

  const breakdownByResource: Record<string, ResourceDailyAggregate[]> = {
    energy: [],
    food: [],
    material: [],
    components: [],
    compute: [],
  };

  for (const row of result.rows) {
    if (breakdownByResource[row.resource]) {
      breakdownByResource[row.resource].push({
        game_day: Number(row.game_day),
        resource: row.resource,
        total_inflow: Number(row.total_inflow),
        total_outflow: Number(row.total_outflow),
        net_change: Number(row.net_change),
        ending_balance: 0,
      });
    }
  }

  return breakdownByResource;
}
