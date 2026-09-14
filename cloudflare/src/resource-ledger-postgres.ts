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
  return repository.transaction((tx) => mutateResourceBalanceInTransaction(tx, input));
}

async function mutateResourceBalanceInTransaction(
  tx: PostgresRepository,
  input: MutateResourceInput,
): Promise<MutateResourceResult> {
  throw new Error(`Canonical resource account unavailable for ${input.ownerId}/${input.resource}`);
}

/**
 * V2 bridge for discrete inventory mutations. A resource change is posted as
 * double-entry accounting (inventory against an issuance or consumption
 * account), then mirrored to the legacy projection until cutover is complete.
 */
export async function postEconomicResourceMutation(
  repository: PostgresRepository,
  input: MutateResourceInput,
): Promise<MutateResourceResult> {
  return repository.transaction(async (tx) => {
    const assetCode = input.resource.toUpperCase();
    const asset = await tx.query<{ id: number }>('SELECT id FROM economic_assets WHERE code = $1', [assetCode]);
    const assetId = asset.rows[0]?.id;
    if (!assetId) return mutateResourceBalanceInTransaction(tx, input);

    const inventory = await tx.query<{ economic_account_id: string }>(
      `SELECT a.id::TEXT AS economic_account_id
         FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE (o.id = $1 OR o.id = (SELECT h.house_id FROM humans h WHERE h.id = $1))
          AND a.asset_id = $2 AND a.account_type = 'INVENTORY' AND a.status = 'ACTIVE'`,
      [input.ownerId, assetId],
    );
    const system = await tx.query<{ account_id: string; economic_id: string }>(
      `SELECT a.id::TEXT AS account_id, o.economic_id::TEXT AS economic_id
         FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id
        WHERE o.economic_id = $2 AND a.asset_id = $1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'`,
      [assetId, input.delta >= 0 ? 'ECON-RESOURCE-PRODUCTION' : 'ECON-RESOURCE-CONSUMPTION'],
    );
    if (!inventory.rows[0] || !system.rows[0]) return mutateResourceBalanceInTransaction(tx, input);

    const amountUnits = BigInt(Math.round(Math.abs(input.delta) * (assetId === 1 ? 100 : 1_000_000)));
    if (amountUnits === 0n) return mutateResourceBalanceInTransaction(tx, input);
    const inventoryId = inventory.rows[0].economic_account_id;
    const systemId = system.rows[0].account_id;
    const entries = input.delta >= 0
      ? [
          { account_id: systemId, asset_id: assetId, delta_units: (-amountUnits).toString(), reason_code: input.reasonType },
          { account_id: inventoryId, asset_id: assetId, delta_units: amountUnits.toString(), reason_code: input.reasonType },
        ]
      : [
          { account_id: inventoryId, asset_id: assetId, delta_units: (-amountUnits).toString(), reason_code: input.reasonType },
          { account_id: systemId, asset_id: assetId, delta_units: amountUnits.toString(), reason_code: input.reasonType },
        ];
    const correlationId = input.correlationId ?? `resource:${input.ownerId}:${input.resource}:${input.reasonType}:${input.reasonId ?? 'none'}:${input.gameDay ?? 0}`;
    const posted = await tx.query<{ transaction_id: string; created: boolean }>(
      'SELECT transaction_id, created FROM earth_post_transaction($1,$2,$3,$4,$5,$6,$7,$8::jsonb)',
      [correlationId, input.gameDay ?? 0, input.gameMinute ?? 0, input.delta >= 0 ? 'RESOURCE_PRODUCTION' : 'RESOURCE_CONSUMPTION', input.delta >= 0 ? 'SYSTEM_PRODUCTION' : 'SYSTEM_CONSUMPTION', input.reasonId ?? null, 'resource-v3', JSON.stringify(entries)],
    );
    const postedRow = posted.rows[0];
    if (!postedRow) throw new Error('V2 resource transaction returned no result');

    const legacy = { status: postedRow.created ? 'success' : 'already_processed', ledgerId: postedRow.transaction_id, ownerId: input.ownerId, resource: input.resource, delta: input.delta, balanceAfter: 0, alreadyProcessed: !postedRow.created } as MutateResourceResult;
    return {
      ...legacy,
      status: postedRow.created ? legacy.status : 'already_processed',
      ledgerId: postedRow.transaction_id,
      alreadyProcessed: !postedRow.created || legacy.alreadyProcessed,
    };
  });
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
  return repository.transaction(async (tx) => {
    const res = await tx.query<ResourceRateHistoryRow>(
      'SELECT NULL::bigint AS id, $1::text AS owner_id, COALESCE($4, 0)::bigint AS game_day, COALESCE($5, 0)::integer AS game_minute, CURRENT_TIMESTAMP AS created_at, $2::text AS trigger_event, $3::text AS trigger_entity_id, NULL::text AS resource, 0::bigint AS gross_inflow, 0::bigint AS gross_outflow, 0::bigint AS tax_amount, 0::bigint AS net_daily_rate WHERE false',
      [ownerId, triggerEvent, triggerEntityId ?? null, gameDay ?? null, gameMinute ?? null],
    );
    return res.rows;
  });
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
      `SELECT e.id::text AS id, t.game_day, t.game_minute, a.owner_economic_id AS owner_id,
              asset.code::text AS resource, e.delta_units AS delta, a.balance_units AS balance_after,
              t.transaction_kind AS reason_type, t.source_id AS reason_id, t.correlation_id, t.created_at
       FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
       JOIN economic_accounts a ON a.id = e.account_id JOIN economic_assets asset ON asset.id = e.asset_id
       WHERE a.owner_economic_id = $1 AND LOWER(asset.code) = UPPER($2)
       ORDER BY t.game_day DESC, t.created_at DESC
       LIMIT $3 OFFSET $4`,
      [ownerId, options.resource, limit, offset],
    );
    return res.rows;
  }

  const res = await repository.query<ResourceLedgerRow>(
    `SELECT e.id::text AS id, t.game_day, t.game_minute, a.owner_economic_id AS owner_id,
            asset.code::text AS resource, e.delta_units AS delta, a.balance_units AS balance_after,
            t.transaction_kind AS reason_type, t.source_id AS reason_id, t.correlation_id, t.created_at
     FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
     JOIN economic_accounts a ON a.id = e.account_id JOIN economic_assets asset ON asset.id = e.asset_id
     WHERE a.owner_economic_id = $1 AND asset.asset_kind = 'RESOURCE'
     ORDER BY t.game_day DESC, t.created_at DESC
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
      `SELECT NULL::bigint AS id, $1::text AS owner_id, 0::bigint AS game_day, 0::integer AS game_minute, CURRENT_TIMESTAMP AS created_at, ''::text AS trigger_event, NULL::text AS trigger_entity_id, $2::text AS resource, 0::bigint AS gross_inflow, 0::bigint AS gross_outflow, 0::bigint AS tax_amount, 0::bigint AS net_daily_rate WHERE false`,
      [ownerId, options.resource, limit, offset],
    );
    return res.rows;
  }

  const res = await repository.query<ResourceRateHistoryRow>(
    `SELECT NULL::bigint AS id, $1::text AS owner_id, 0::bigint AS game_day, 0::integer AS game_minute, CURRENT_TIMESTAMP AS created_at, ''::text AS trigger_event, NULL::text AS trigger_entity_id, NULL::text AS resource, 0::bigint AS gross_inflow, 0::bigint AS gross_outflow, 0::bigint AS tax_amount, 0::bigint AS net_daily_rate WHERE false`,
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
       t.game_day,
       asset.code AS resource,
       COALESCE(SUM(CASE WHEN e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0) AS total_inflow,
       COALESCE(SUM(CASE WHEN e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END), 0) AS total_outflow,
       COALESCE(SUM(e.delta_units), 0) AS net_change
     FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
     JOIN economic_accounts a ON a.id = e.account_id JOIN economic_assets asset ON asset.id = e.asset_id
     WHERE a.owner_economic_id = $1 AND asset.asset_kind = 'RESOURCE'
     GROUP BY t.game_day, asset.code
     ORDER BY t.game_day DESC
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
