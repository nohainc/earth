import { evaluateInventoryPolicy, evaluateSalePolicy, type HousePolicy, type PolicyEvaluation, type PolicyReasonCode } from './house-policy.ts';
import type { PostgresRepository } from './repository.ts';
import { submitMarketOrder } from './market-postgres.ts';
import { unitsToDisplayQuantity, priceUnitsToDisplayPrice } from './market-units.ts';

export type CompiledPolicyAction = {
  actionType: 'BUY' | 'SELL';
  product: string;
  side: 'buy' | 'sell';
  quantityUnits: bigint;
  limitPriceUnits: bigint;
  source: 'HOUSE_POLICY';
  reasonCode: PolicyReasonCode;
  reason: string;
};

export type PolicyException = {
  product: string;
  action: 'BUY' | 'SELL';
  reasonCode: PolicyReasonCode;
  reason: string;
};

export type CompiledPolicy = {
  actions: CompiledPolicyAction[];
  exceptions: PolicyException[];
};

export type PolicyExecutionStatus = 'NO_ACTION' | 'ORDER_PLACED' | 'PARTIALLY_FILLED' | 'FILLED' | 'EXPIRED' | 'SKIPPED' | 'FAILED';

function executionStatusForOrder(orderStatus: unknown): PolicyExecutionStatus {
  switch (String(orderStatus ?? '').toUpperCase()) {
    case 'PARTIAL': return 'PARTIALLY_FILLED';
    case 'FILLED': return 'FILLED';
    case 'CANCELLED': return 'EXPIRED';
    default: return 'ORDER_PLACED';
  }
}

async function refreshAndSummarizeExecution(
  repository: PostgresRepository,
  houseId: string,
  automationVersionId: string,
  gameDay: number,
  evaluatedAtGameMinute: number,
  noAction: boolean,
): Promise<void> {
  await repository.query(
    `UPDATE policy_execution_log log
        SET market_order_status = order_row.status,
            execution_status = CASE order_row.status
              WHEN 'PARTIAL' THEN 'PARTIALLY_FILLED'
              WHEN 'FILLED' THEN 'FILLED'
              WHEN 'CANCELLED' THEN 'EXPIRED'
              ELSE 'ORDER_PLACED'
            END,
            updated_at = CURRENT_TIMESTAMP
       FROM market_orders order_row
      WHERE log.house_id = $1 AND log.game_day = $2
        AND log.market_order_id = order_row.id`,
    [houseId, gameDay],
  );
  const counts = await repository.query<{
    order_placed: string; partially_filled: string; filled: string; expired: string;
    skipped: string; failed: string; reason_codes: string[] | null;
  }>(
    `SELECT
       COUNT(*) FILTER (WHERE execution_status = 'ORDER_PLACED')::TEXT AS order_placed,
       COUNT(*) FILTER (WHERE execution_status = 'PARTIALLY_FILLED')::TEXT AS partially_filled,
       COUNT(*) FILTER (WHERE execution_status = 'FILLED')::TEXT AS filled,
       COUNT(*) FILTER (WHERE execution_status = 'EXPIRED')::TEXT AS expired,
       COUNT(*) FILTER (WHERE execution_status = 'SKIPPED')::TEXT AS skipped,
       COUNT(*) FILTER (WHERE execution_status = 'FAILED')::TEXT AS failed,
       COALESCE(array_agg(DISTINCT reason_code) FILTER (WHERE reason_code IS NOT NULL), ARRAY[]::TEXT[]) AS reason_codes
       FROM policy_execution_log
      WHERE house_id = $1 AND game_day = $2`,
    [houseId, gameDay],
  );
  const row = counts.rows[0] ?? { order_placed: '0', partially_filled: '0', filled: '0', expired: '0', skipped: '0', failed: '0', reason_codes: [] };
  await repository.query(
    `INSERT INTO policy_execution_daily_summaries (
       house_id, automation_version_id, game_day, evaluated_at_game_minute,
       no_action_count, order_placed_count, partially_filled_count, filled_count,
       expired_count, skipped_count, failed_count, reason_codes
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::JSONB)
     ON CONFLICT (house_id, game_day, automation_version_id) DO UPDATE SET
       evaluated_at_game_minute = EXCLUDED.evaluated_at_game_minute,
       no_action_count = EXCLUDED.no_action_count,
       order_placed_count = EXCLUDED.order_placed_count,
       partially_filled_count = EXCLUDED.partially_filled_count,
       filled_count = EXCLUDED.filled_count,
       expired_count = EXCLUDED.expired_count,
       skipped_count = EXCLUDED.skipped_count,
       failed_count = EXCLUDED.failed_count,
       reason_codes = EXCLUDED.reason_codes,
       updated_at = CURRENT_TIMESTAMP`,
    [
      houseId, automationVersionId, gameDay, evaluatedAtGameMinute, noAction ? 1 : 0,
      Number(row.order_placed), Number(row.partially_filled), Number(row.filled),
      Number(row.expired), Number(row.skipped), Number(row.failed), JSON.stringify(row.reason_codes ?? []),
    ],
  );
  // Keep idempotency rows bounded. The daily summary is the durable history.
  await repository.query(
    `DELETE FROM policy_execution_log WHERE house_id = $1 AND game_day < $2`,
    [houseId, Math.max(1, gameDay - 90)],
  );
}

function compileBuy(policy: HousePolicy, evaluation: PolicyEvaluation, dailySpendUsedUnits: bigint): CompiledPolicyAction | PolicyException {
  const product = evaluation.product;
  if (evaluation.priceLimitUnits === null || evaluation.priceLimitUnits <= 0n) {
    return { product, action: 'BUY', reasonCode: 'MISSING_BUY_PRICE', reason: 'A positive maximum input price is required before a policy can place a buy order' };
  }
  const remainingSpend = policy.dailySpendCapUnits - dailySpendUsedUnits;
  // Quantity is stored in millionths of a resource unit while price is in
  // CREDIT cents per unit. Keep the inverse calculation dimensionally
  // consistent with settlement's quantity*price/1_000_000 formula.
  const boundedQuantity =
    (remainingSpend * 1_000_000n) / evaluation.priceLimitUnits;
  const quantity = evaluation.quantityUnits < boundedQuantity ? evaluation.quantityUnits : boundedQuantity;
  if (quantity <= 0n) return { product, action: 'BUY', reasonCode: 'SPEND_CAP_EXHAUSTED', reason: 'The daily policy spend cap has no remaining capacity' };
  return { actionType: 'BUY', product, side: 'buy', quantityUnits: quantity, limitPriceUnits: evaluation.priceLimitUnits, source: 'HOUSE_POLICY', reasonCode: evaluation.reasonCode, reason: evaluation.reason };
}

function compileSell(evaluation: PolicyEvaluation): CompiledPolicyAction | PolicyException {
  if (!evaluation.priceLimitUnits || evaluation.priceLimitUnits <= 0n) {
    return { product: evaluation.product, action: 'SELL', reasonCode: 'MISSING_SELL_PRICE', reason: 'A positive minimum sale price is required before a policy can place a sell order' };
  }
  return { actionType: 'SELL', product: evaluation.product, side: 'sell', quantityUnits: evaluation.quantityUnits, limitPriceUnits: evaluation.priceLimitUnits, source: 'HOUSE_POLICY', reasonCode: evaluation.reasonCode, reason: evaluation.reason };
}

export function compileHousePolicy(policy: HousePolicy, inventory: Record<string, bigint | string | number>, dailySpendUsedUnits: bigint): CompiledPolicy {
  const evaluations = [...evaluateInventoryPolicy(policy, inventory, dailySpendUsedUnits), ...evaluateSalePolicy(policy, inventory)];
  const actions: CompiledPolicyAction[] = [];
  const exceptions: PolicyException[] = [];
  let remainingSpend = policy.dailySpendCapUnits - dailySpendUsedUnits;
  for (const evaluation of evaluations) {
    const result = evaluation.action === 'BUY'
      ? compileBuy(policy, evaluation, policy.dailySpendCapUnits - remainingSpend)
      : compileSell(evaluation);
    if ('actionType' in result) {
      actions.push(result);
      if (result.actionType === 'BUY') {
        remainingSpend = remainingSpend -
            ((result.quantityUnits * result.limitPriceUnits + 500_000n) /
                1_000_000n);
        if (remainingSpend < 0n) remainingSpend = 0n;
      }
    } else exceptions.push(result);
  }
  return { actions, exceptions };
}

type StoredPolicyRow = Omit<HousePolicy, 'policyType' | 'minimumReserveUnits' | 'sellAboveUnits' | 'maxInputPriceUnits' | 'minSalePriceUnits' | 'maxBuyQuantityUnits' | 'maxSellQuantityUnits' | 'dailySpendCapUnits'> & {
  daily_spend_cap_units: string;
  minimum_reserve_units: Record<string, string>;
  sell_above_units: Record<string, string>;
  max_input_price_units: Record<string, string>;
  min_sale_price_units: Record<string, string>;
  max_buy_quantity_units: Record<string, string>;
  max_sell_quantity_units: Record<string, string>;
};

function storedPolicy(row: StoredPolicyRow): HousePolicy {
  const map = (value: Record<string, string>) => Object.fromEntries(Object.entries(value ?? {}).map(([key, raw]) => [key.toUpperCase(), BigInt(raw)]));
  return {
    id: row.id, houseId: row.houseId, policyType: 'OPERATING', version: row.version,
    effectiveFromGameDay: row.effectiveFromGameDay, status: row.status, operatingMode: row.operatingMode,
    dailySpendCapUnits: BigInt(row.daily_spend_cap_units), minimumReserveUnits: map(row.minimum_reserve_units), sellAboveUnits: map(row.sell_above_units),
    maxInputPriceUnits: map(row.max_input_price_units), minSalePriceUnits: map(row.min_sale_price_units),
    maxBuyQuantityUnits: map(row.max_buy_quantity_units), maxSellQuantityUnits: map(row.max_sell_quantity_units), rulesVersion: row.rulesVersion,
  };
}

function inventoryMap(rows: Array<{ code: string; balance_units: string }>): Record<string, bigint> {
  return Object.fromEntries(rows.map((row) => [row.code.toUpperCase(), BigInt(row.balance_units)]));
}

/** Execute only policies effective for a newly completed day. Every order uses
 * the normal market escrow path; the policy log is an audit/idempotency ledger,
 * not a second economic authority. */
export async function executeHousePoliciesForDay(
  repository: PostgresRepository,
  gameDay: number,
  options: { shard?: number; shardCount?: number } = {},
): Promise<{ actions: number; exceptions: number }> {
  const shardFilter = options.shard !== undefined && options.shardCount !== undefined
    ? 'AND mod(abs(hashtextextended(house_id, 0)), $2) = $3'
    : '';
  const params: unknown[] = [gameDay];
  if (options.shard !== undefined && options.shardCount !== undefined) {
    params.push(options.shardCount, options.shard);
  }
  const policies = await repository.query<StoredPolicyRow>(
    `WITH resolved AS (
       SELECT id, house_id AS "houseId", version,
            effective_from_game_day AS "effectiveFromGameDay", status, enabled,
            operating_mode AS "operatingMode", daily_spend_cap_units::TEXT AS daily_spend_cap_units,
            minimum_reserve_units, sell_above_units, max_input_price_units,
            min_sale_price_units, max_buy_quantity_units, max_sell_quantity_units,
            rules_version AS "rulesVersion",
            row_number() OVER (PARTITION BY house_id ORDER BY effective_from_game_day DESC, version DESC) AS resolved_rank
       FROM house_automation_versions
      WHERE status = 'ACTIVE' AND enabled = TRUE AND effective_from_game_day <= $1
      ${shardFilter}
    )
    SELECT id, "houseId", version, "effectiveFromGameDay", status, enabled, "operatingMode",
           daily_spend_cap_units, minimum_reserve_units, sell_above_units, max_input_price_units,
           min_sale_price_units, max_buy_quantity_units, max_sell_quantity_units, "rulesVersion"
      FROM resolved
     WHERE resolved_rank = 1
     ORDER BY "houseId"`,
    params,
  );
  let actions = 0;
  let exceptions = 0;
  for (const row of policies.rows) {
    const policy = storedPolicy(row);
    const human = (await repository.query<{ id: string }>("SELECT id FROM humans WHERE house_id = $1 AND status = 'ACTIVE' ORDER BY id LIMIT 1", [policy.houseId])).rows[0];
    if (!human) continue;
    const inventory = await repository.query<{ code: string; balance_units: string }>(
      `SELECT asset.code, COALESCE(account.balance_units, 0)::TEXT AS balance_units
         FROM economic_assets asset
         LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
         LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id
          AND account.asset_id = asset.id AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
        WHERE asset.asset_kind = 'RESOURCE' ORDER BY asset.id`, [policy.houseId],
    );
    const spendRows = await repository.query<{ spend_units: string }>(
      `SELECT COALESCE(SUM((decision->>'spendUnits')::BIGINT), 0)::TEXT AS spend_units
         FROM policy_execution_log WHERE house_id = $1 AND game_day = $2 AND action_type = 'BUY'`, [policy.houseId, gameDay],
    );
    const compiled = compileHousePolicy(policy, inventoryMap(inventory.rows), BigInt(spendRows.rows[0]?.spend_units ?? '0'));
    for (const exception of compiled.exceptions) {
      const correlationId = `house-policy:${policy.id}:${gameDay}:exception:${exception.action}:${exception.product}`;
      await repository.query(
        `INSERT INTO policy_execution_log (policy_id, automation_version_id, house_id, game_day, action_type, action_correlation_id, decision, execution_status, reason_code, evaluated_at_game_minute)
         VALUES (NULL, $1, $2, $3, 'EXCEPTION', $4, $5::JSONB, 'SKIPPED', $6, 1439) ON CONFLICT (action_correlation_id) DO NOTHING`,
        [policy.id, policy.houseId, gameDay, correlationId, JSON.stringify(exception), exception.reasonCode],
      );
      exceptions += 1;
    }
    const openOrders = await repository.query<{ product: string; side: string }>(
      `SELECT lower(regexp_replace(i.symbol, '^SPOT-', '')) AS product, lower(o.side) AS side
         FROM market_orders o
         JOIN owner_registry owner ON owner.economic_id = o.owner_economic_id
         JOIN market_instruments i ON i.id = o.instrument_id
        WHERE owner.id = $1 AND o.source_type = 'HOUSE_POLICY'
          AND o.status IN ('OPEN', 'PARTIAL')`,
      [policy.houseId],
    );
    const openOrderKeys = new Set(openOrders.rows.map((order) => `${order.product.toUpperCase()}:${order.side.toUpperCase()}`));
    for (const action of compiled.actions) {
      const correlationId = `house-policy:${policy.id}:${gameDay}:${action.actionType}:${action.product}`;
      const already = await repository.query('SELECT 1 FROM policy_execution_log WHERE action_correlation_id = $1', [correlationId]);
      if (already.rows[0]) continue;
      const openOrderKey = `${action.product.toUpperCase()}:${action.side.toUpperCase()}`;
      if (openOrderKeys.has(openOrderKey)) {
        await repository.query(
          `INSERT INTO policy_execution_log (policy_id, automation_version_id, house_id, game_day, action_type, action_correlation_id, decision, execution_status, reason_code, evaluated_at_game_minute)
           VALUES (NULL, $1, $2, $3, $4, $5, $6::JSONB, 'SKIPPED', 'OPEN_ORDER_EXISTS', 1439) ON CONFLICT (action_correlation_id) DO NOTHING`,
          [policy.id, policy.houseId, gameDay, action.actionType, correlationId, JSON.stringify({ product: action.product, side: action.side, reasonCode: 'OPEN_ORDER_EXISTS' })],
        );
        continue;
      }
      try {
        const submission = await submitMarketOrder(repository, {
          humanId: human.id,
          product: action.product.toLowerCase(),
          side: action.side,
          quantity: unitsToDisplayQuantity(action.quantityUnits),
          limitPrice: priceUnitsToDisplayPrice(action.limitPriceUnits),
          correlationId,
          sourceType: 'HOUSE_POLICY',
          policyId: policy.id,
          goodTilGameDay: gameDay + 1,
        });
        const order = submission.order as Record<string, unknown> | undefined;
        const orderId = order?.id == null ? null : String(order.id);
        const orderStatus = order?.status == null ? 'OPEN' : String(order.status).toUpperCase();
        const executionStatus = executionStatusForOrder(orderStatus);
        const spendUnits = action.actionType === 'BUY' ? ((action.quantityUnits * action.limitPriceUnits + 500_000n) / 1_000_000n).toString() : '0';
        await repository.query(
          `INSERT INTO policy_execution_log (policy_id, automation_version_id, house_id, game_day, action_type, action_correlation_id, decision, execution_status, reason_code, market_order_id, market_order_status, evaluated_at_game_minute)
           VALUES (NULL, $1, $2, $3, $4, $5, $6::JSONB, $7, $8, $9, $10, 1439) ON CONFLICT (action_correlation_id) DO NOTHING`,
          [policy.id, policy.houseId, gameDay, action.actionType, correlationId, JSON.stringify({ product: action.product, side: action.side, quantityUnits: action.quantityUnits.toString(), limitPriceUnits: action.limitPriceUnits.toString(), spendUnits, orderId, orderStatus }), executionStatus, action.reasonCode, orderId, orderStatus],
        );
        actions += 1;
      } catch (error) {
        const failure = { product: action.product, side: action.side, quantityUnits: action.quantityUnits.toString(), limitPriceUnits: action.limitPriceUnits.toString(), error: error instanceof Error ? error.message : 'Policy order failed' };
        await repository.query(
          `INSERT INTO policy_execution_log (policy_id, automation_version_id, house_id, game_day, action_type, action_correlation_id, decision, execution_status, reason_code, evaluated_at_game_minute)
           VALUES (NULL, $1, $2, $3, 'EXCEPTION', $4, $5::JSONB, 'FAILED', 'ORDER_SUBMISSION_FAILED', 1439) ON CONFLICT (action_correlation_id) DO NOTHING`,
          [policy.id, policy.houseId, gameDay, `${correlationId}:exception`, JSON.stringify(failure)],
        );
        exceptions += 1;
      }
    }
    await refreshAndSummarizeExecution(repository, policy.houseId, policy.id, gameDay, 1439, compiled.actions.length === 0 && compiled.exceptions.length === 0);
  }
  return { actions, exceptions };
}
