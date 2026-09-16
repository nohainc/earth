import { evaluateInventoryPolicy, evaluateSalePolicy, type HousePolicy, type PolicyEvaluation } from './house-policy.ts';
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
  reason: string;
};

export type PolicyException = {
  product: string;
  action: 'BUY' | 'SELL';
  reason: string;
};

export type CompiledPolicy = {
  actions: CompiledPolicyAction[];
  exceptions: PolicyException[];
};

function compileBuy(policy: HousePolicy, evaluation: PolicyEvaluation, dailySpendUsedUnits: bigint): CompiledPolicyAction | PolicyException {
  const product = evaluation.product;
  if (evaluation.priceLimitUnits === null || evaluation.priceLimitUnits <= 0n) {
    return { product, action: 'BUY', reason: 'A positive maximum input price is required before a policy can place a buy order' };
  }
  const remainingSpend = policy.dailySpendCapUnits - dailySpendUsedUnits;
  // Quantity is stored in millionths of a resource unit while price is in
  // CREDIT cents per unit. Keep the inverse calculation dimensionally
  // consistent with settlement's quantity*price/1_000_000 formula.
  const boundedQuantity =
    (remainingSpend * 1_000_000n) / evaluation.priceLimitUnits;
  const quantity = evaluation.quantityUnits < boundedQuantity ? evaluation.quantityUnits : boundedQuantity;
  if (quantity <= 0n) return { product, action: 'BUY', reason: 'The daily policy spend cap has no remaining capacity' };
  return { actionType: 'BUY', product, side: 'buy', quantityUnits: quantity, limitPriceUnits: evaluation.priceLimitUnits, source: 'HOUSE_POLICY', reason: evaluation.reason };
}

function compileSell(evaluation: PolicyEvaluation): CompiledPolicyAction | PolicyException {
  if (!evaluation.priceLimitUnits || evaluation.priceLimitUnits <= 0n) {
    return { product: evaluation.product, action: 'SELL', reason: 'A positive minimum sale price is required before a policy can place a sell order' };
  }
  return { actionType: 'SELL', product: evaluation.product, side: 'sell', quantityUnits: evaluation.quantityUnits, limitPriceUnits: evaluation.priceLimitUnits, source: 'HOUSE_POLICY', reason: evaluation.reason };
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

type StoredPolicyRow = Omit<HousePolicy, 'reserveFloorUnits' | 'maxInputPriceUnits' | 'minSalePriceUnits' | 'procurementQuantityUnits' | 'dailySpendCapUnits'> & {
  daily_spend_cap_units: string;
  reserve_floor_units: Record<string, string>;
  max_input_price_units: Record<string, string>;
  min_sale_price_units: Record<string, string>;
  procurement_quantity_units: Record<string, string>;
};

function storedPolicy(row: StoredPolicyRow): HousePolicy {
  const map = (value: Record<string, string>) => Object.fromEntries(Object.entries(value ?? {}).map(([key, raw]) => [key.toUpperCase(), BigInt(raw)]));
  return {
    id: row.id, houseId: row.houseId, policyType: row.policyType, version: row.version,
    effectiveFromGameDay: row.effectiveFromGameDay, status: row.status, operatingMode: row.operatingMode,
    dailySpendCapUnits: BigInt(row.daily_spend_cap_units), reserveFloorUnits: map(row.reserve_floor_units),
    maxInputPriceUnits: map(row.max_input_price_units), minSalePriceUnits: map(row.min_sale_price_units),
    procurementQuantityUnits: map(row.procurement_quantity_units), rulesVersion: row.rulesVersion,
  };
}

function inventoryMap(rows: Array<{ code: string; balance_units: string }>): Record<string, bigint> {
  return Object.fromEntries(rows.map((row) => [row.code.toUpperCase(), BigInt(row.balance_units)]));
}

/** Execute only policies effective for a newly completed day. Every order uses
 * the normal market escrow path; the policy log is an audit/idempotency ledger,
 * not a second economic authority. */
export async function executeHousePoliciesForDay(repository: PostgresRepository, gameDay: number): Promise<{ actions: number; exceptions: number }> {
  const policies = await repository.query<StoredPolicyRow>(
    `SELECT DISTINCT ON (house_id) id, house_id AS "houseId", policy_type AS "policyType", version,
            effective_from_game_day AS "effectiveFromGameDay", status,
            operating_mode AS "operatingMode", daily_spend_cap_units::TEXT AS daily_spend_cap_units,
            reserve_floor_units AS reserve_floor_units, max_input_price_units AS max_input_price_units,
            min_sale_price_units AS min_sale_price_units, procurement_quantity_units AS procurement_quantity_units,
            rules_version AS "rulesVersion"
       FROM house_operating_policies
      WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
      ORDER BY house_id, effective_from_game_day DESC, version DESC`, [gameDay],
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
        `INSERT INTO policy_execution_log (policy_id, house_id, game_day, action_type, action_correlation_id, decision)
         VALUES ($1, $2, $3, 'EXCEPTION', $4, $5::JSONB) ON CONFLICT (action_correlation_id) DO NOTHING`,
        [policy.id, policy.houseId, gameDay, correlationId, JSON.stringify(exception)],
      );
      exceptions += 1;
    }
    for (const action of compiled.actions) {
      const correlationId = `house-policy:${policy.id}:${gameDay}:${action.actionType}:${action.product}`;
      const already = await repository.query('SELECT 1 FROM policy_execution_log WHERE action_correlation_id = $1', [correlationId]);
      if (already.rows[0]) continue;
      try {
        await submitMarketOrder(repository, {
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
        const spendUnits = action.actionType === 'BUY' ? ((action.quantityUnits * action.limitPriceUnits + 500_000n) / 1_000_000n).toString() : '0';
        await repository.query(
          `INSERT INTO policy_execution_log (policy_id, house_id, game_day, action_type, action_correlation_id, decision)
           VALUES ($1, $2, $3, $4, $5, $6::JSONB) ON CONFLICT (action_correlation_id) DO NOTHING`,
          [policy.id, policy.houseId, gameDay, action.actionType, correlationId, JSON.stringify({ ...action, quantityUnits: action.quantityUnits.toString(), limitPriceUnits: action.limitPriceUnits.toString(), spendUnits })],
        );
        actions += 1;
      } catch (error) {
        const failure = { ...action, quantityUnits: action.quantityUnits.toString(), limitPriceUnits: action.limitPriceUnits.toString(), error: error instanceof Error ? error.message : 'Policy order failed' };
        await repository.query(
          `INSERT INTO policy_execution_log (policy_id, house_id, game_day, action_type, action_correlation_id, decision)
           VALUES ($1, $2, $3, 'EXCEPTION', $4, $5::JSONB) ON CONFLICT (action_correlation_id) DO NOTHING`,
          [policy.id, policy.houseId, gameDay, `${correlationId}:exception`, JSON.stringify(failure)],
        );
        exceptions += 1;
      }
    }
  }
  return { actions, exceptions };
}
