import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { parseCreditAmount, centsToMoney } from './money.ts';
import { formatFixedUnits } from './units.ts';
import { priceUnitsToDisplayPrice, unitsToDisplayQuantity } from './market-units.ts';
import { compileHousePolicy } from './house-policy-execution.ts';
import { readMarketOrderRows, serializeMarketOrder } from './market-order-read-model.ts';

type PolicyInput = {
  policyType: 'OPERATING' | 'INVENTORY_RESERVE' | 'MARKET_STANDING';
  /** @deprecated Retained only for legacy policy rows; automation execution ignores presets. */
  operatingMode?: 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM';
  effectiveFromGameDay?: number;
  dailySpendCap?: string;
  minimumReserve?: Record<string, string | number>;
  sellAbove?: Record<string, string | number>;
  maxInputPrice?: Record<string, string | number>;
  minSalePrice?: Record<string, string | number>;
  maxBuyQuantity?: Record<string, string | number>;
  maxSellQuantity?: Record<string, string | number>;
  enabled?: boolean;
  correlationId: string;
};
export type HouseAutomationInput = Omit<PolicyInput, 'policyType' | 'correlationId' | 'operatingMode'> & { correlationId?: string };

const CANONICAL_RESOURCES = new Set(['FOOD', 'ENERGY', 'MATERIAL', 'COMPONENTS', 'COMPUTE']);
const BIGINT_MAX = 9_223_372_036_854_775_807n;

function decimalMap(value: Record<string, string | number> = {}, scale: bigint, decimals: number, label: string, positive = false): Record<string, string> {
  return Object.fromEntries(Object.entries(value).map(([key, raw]) => {
    const resource = key.toUpperCase();
    if (!CANONICAL_RESOURCES.has(resource)) throw new Error(`${label} contains unknown resource code ${key}`);
    const text = String(raw).trim();
    if (!new RegExp(`^\\d+(?:\\.\\d{1,${decimals}})?$`).test(text)) throw new Error(`${label} value for ${key} must be a non-negative decimal`);
    const [whole, fraction = ''] = text.split('.');
    const units = BigInt(whole) * scale + BigInt(fraction.padEnd(decimals, '0') || '0');
    if (units > BIGINT_MAX || (positive && units <= 0n)) throw new Error(`${label} value for ${key} is outside the supported bounds`);
    return [resource, units.toString()];
  }));
}

type AutomationRuleMaps = Pick<PolicyInput, 'minimumReserve' | 'sellAbove' | 'maxInputPrice' | 'minSalePrice' | 'maxBuyQuantity' | 'maxSellQuantity'>;

function normalizedPolicyMaps(input: AutomationRuleMaps): {
  minimumReserve: Record<string, string>;
  sellAbove: Record<string, string>;
  maxInputPrice: Record<string, string>;
  minSalePrice: Record<string, string>;
  maxBuyQuantity: Record<string, string>;
  maxSellQuantity: Record<string, string>;
} {
  const minimumReserve = decimalMap(input.minimumReserve, 1_000_000n, 6, 'minimumReserve');
  const sellAbove = decimalMap(input.sellAbove, 1_000_000n, 6, 'sellAbove');
  const maxInputPrice = decimalMap(input.maxInputPrice, 100n, 2, 'maxInputPrice', true);
  const minSalePrice = decimalMap(input.minSalePrice, 100n, 2, 'minSalePrice', true);
  const maxBuyQuantity = decimalMap(input.maxBuyQuantity, 1_000_000n, 6, 'maxBuyQuantity');
  const maxSellQuantity = decimalMap(input.maxSellQuantity, 1_000_000n, 6, 'maxSellQuantity');
  for (const [asset, threshold] of Object.entries(sellAbove)) {
    if (BigInt(threshold) < BigInt(minimumReserve[asset] ?? '0')) {
      throw new Error(`sellAbove for ${asset} cannot be below minimumReserve`);
    }
  }
  return { minimumReserve, sellAbove, maxInputPrice, minSalePrice, maxBuyQuantity, maxSellQuantity };
}

function displayMap(value: unknown, scale: bigint, decimals: number): Record<string, string> {
  if (!value || typeof value !== 'object') return {};
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, raw]) => [key, formatFixedUnits(BigInt(String(raw)), scale, decimals)]));
}

function displayPolicy(row: Record<string, any>): Record<string, unknown> {
  return {
    id: row.id, version: Number(row.version),
    effectiveFromGameDay: Number(row.effective_from_game_day), status: row.status,
    enabled: row.enabled === true,
    dailySpendCap: centsToMoney(BigInt(String(row.daily_spend_cap_units ?? '0'))),
    minimumReserve: displayMap(row.minimum_reserve_units ?? row.reserve_floor_units, 1_000_000n, 6),
    sellAbove: displayMap(row.sell_above_units ?? row.reserve_floor_units, 1_000_000n, 6),
    maxInputPrice: displayMap(row.max_input_price_units, 100n, 2),
    minSalePrice: displayMap(row.min_sale_price_units, 100n, 2),
    maxBuyQuantity: displayMap(row.max_buy_quantity_units ?? row.procurement_quantity_units, 1_000_000n, 6),
    maxSellQuantity: displayMap(row.max_sell_quantity_units, 1_000_000n, 6),
    rules_version: row.rules_version,
  };
}

export async function listHousePolicies(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units::TEXT, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version FROM house_operating_policies WHERE house_id = $1 ORDER BY policy_type, version DESC`, [houseId]);
  return { policies: result.rows.map(displayPolicy), generatedFrom: 'postgres-canonical-facts' };
}

/** Read model for the single player-facing automation configuration. */
export async function getHouseAutomation(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const day = (await readAuthoritativeGameTime(repository)).gameDay;
  const [policies, inventory, prices, orders, history] = await Promise.all([
    repository.query(`SELECT id, version, effective_from_game_day, status, operating_mode, enabled,
             daily_spend_cap_units::TEXT, minimum_reserve_units, sell_above_units, max_input_price_units,
             min_sale_price_units, max_buy_quantity_units, max_sell_quantity_units, rules_version
             FROM house_automation_versions
       WHERE house_id = $1 AND status = 'ACTIVE'
       ORDER BY effective_from_game_day ASC, version DESC`, [houseId]),
    repository.query(`SELECT asset.code, COALESCE(account.balance_units, 0)::TEXT AS balance_units
        FROM economic_assets asset
        LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
        LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id
          AND account.asset_id = asset.id AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
       WHERE asset.asset_kind = 'RESOURCE'
       ORDER BY asset.id`, [houseId]),
    repository.query(`SELECT i.id, i.symbol, i.genesis_reference_price_units::TEXT,
             s.last_clearing_price_units::TEXT, s.best_bid_units::TEXT, s.best_ask_units::TEXT
        FROM market_instruments i
        LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
       WHERE i.instrument_type = 'SPOT' AND i.status = 'ACTIVE'
       ORDER BY i.id`, []),
    readMarketOrderRows(repository, { ownerRegistryId: houseId, sourceType: 'HOUSE_POLICY', statuses: ['OPEN', 'PARTIAL'], limit: 100 }),
    repository.query(`SELECT game_day AS "gameDay", evaluated_at_game_minute AS "evaluatedAtGameMinute",
             no_action_count AS "noActionCount", order_placed_count AS "orderPlacedCount",
             partially_filled_count AS "partiallyFilledCount", filled_count AS "filledCount",
             expired_count AS "expiredCount", skipped_count AS "skippedCount",
             failed_count AS "failedCount", reason_codes AS "reasonCodes", updated_at AS "updatedAt"
        FROM policy_execution_daily_summaries
       WHERE house_id = $1
       ORDER BY game_day DESC
       LIMIT 30`, [houseId]),
  ]);
  const effective = policies.rows.filter((row) => Number(row.effective_from_game_day) <= day);
  const current = effective.length > 0
    ? [effective.slice().sort((a, b) => Number(b.effective_from_game_day) - Number(a.effective_from_game_day) || Number(b.version) - Number(a.version))[0]]
    : [];
  const scheduled = policies.rows.filter((row) => Number(row.effective_from_game_day) > day);
  const nextEvaluationGameDay = current.length > 0
    ? day + 1
    : (scheduled[0] ? Number(scheduled[0].effective_from_game_day) : null);
  return {
    ok: true,
    enabled: current[0]?.enabled === true,
    current: current[0] ? displayPolicy(current[0]) : null,
    scheduled: scheduled[0] ? displayPolicy(scheduled[0]) : null,
    nextRunGameDay: nextEvaluationGameDay,
    nextEvaluationGameDay,
    currentInventory: Object.fromEntries(inventory.rows.map((row) => [String(row.code), unitsToDisplayQuantity(BigInt(String(row.balance_units)))])),
    referenceMarketPrices: prices.rows.map((row) => ({
      product: String(row.symbol).replace(/^SPOT-/, '').toLowerCase(),
      referencePrice: row.last_clearing_price_units
        ? priceUnitsToDisplayPrice(String(row.last_clearing_price_units))
        : (row.genesis_reference_price_units ? priceUnitsToDisplayPrice(String(row.genesis_reference_price_units)) : null),
      lastClearingPrice: row.last_clearing_price_units ? priceUnitsToDisplayPrice(String(row.last_clearing_price_units)) : null,
      bestBid: row.best_bid_units ? priceUnitsToDisplayPrice(String(row.best_bid_units)) : null,
      bestAsk: row.best_ask_units ? priceUnitsToDisplayPrice(String(row.best_ask_units)) : null,
    })),
    openAutomatedOrders: orders.rows.map(serializeMarketOrder),
    recentExecutionSummaries: history.rows,
    generatedFrom: 'postgres-canonical-facts',
  };
}

/** Preview the exact compiler output without creating orders or a version. */
export async function previewHouseAutomation(repository: PostgresRepository, houseId: string, input: HouseAutomationInput): Promise<Record<string, unknown>> {
  const clock = await readAuthoritativeGameTime(repository);
  const capUnits = parseCreditAmount(input.dailySpendCap ?? '0');
  const maps = normalizedPolicyMaps(input);
  const [inventory, spend] = await Promise.all([
    repository.query<{ code: string; balance_units: string }>(`SELECT asset.code, COALESCE(account.balance_units, 0)::TEXT AS balance_units
        FROM economic_assets asset
        LEFT JOIN owner_registry owner ON owner.id = $1 AND owner.owner_type = 'HOUSE'
        LEFT JOIN economic_accounts account ON account.owner_economic_id = owner.economic_id
          AND account.asset_id = asset.id AND account.account_type = 'INVENTORY' AND account.status = 'ACTIVE'
       WHERE asset.asset_kind = 'RESOURCE' ORDER BY asset.id`, [houseId]),
    repository.query<{ spend_units: string }>(`SELECT COALESCE(SUM((decision->>'spendUnits')::BIGINT), 0)::TEXT AS spend_units
        FROM policy_execution_log WHERE house_id = $1 AND game_day = $2 AND action_type = 'BUY'`, [houseId, clock.gameDay]),
  ]);
  const dailySpendUsedUnits = BigInt(spend.rows[0]?.spend_units ?? '0');
  const policy: import('./house-policy.ts').HousePolicy = {
    id: `preview:${houseId}`, houseId, policyType: 'OPERATING', version: 0,
    effectiveFromGameDay: clock.gameDay, status: 'ACTIVE', operatingMode: 'BALANCED',
    dailySpendCapUnits: capUnits,
    minimumReserveUnits: Object.fromEntries(Object.entries(maps.minimumReserve).map(([key, value]) => [key, BigInt(value)])),
    sellAboveUnits: Object.fromEntries(Object.entries(maps.sellAbove).map(([key, value]) => [key, BigInt(value)])),
    maxInputPriceUnits: Object.fromEntries(Object.entries(maps.maxInputPrice).map(([key, value]) => [key, BigInt(value)])),
    minSalePriceUnits: Object.fromEntries(Object.entries(maps.minSalePrice).map(([key, value]) => [key, BigInt(value)])),
    maxBuyQuantityUnits: Object.fromEntries(Object.entries(maps.maxBuyQuantity).map(([key, value]) => [key, BigInt(value)])),
    maxSellQuantityUnits: Object.fromEntries(Object.entries(maps.maxSellQuantity).map(([key, value]) => [key, BigInt(value)])),
    rulesVersion: 'automation-v1',
  };
  const inventoryMap = Object.fromEntries(inventory.rows.map((row) => [row.code.toUpperCase(), BigInt(row.balance_units)]));
  const disabled = input.enabled === false;
  const compiled = disabled
    ? { actions: [], exceptions: [] as Array<{ product: string; action: 'BUY' | 'SELL'; reason: string }> }
    : compileHousePolicy(policy, inventoryMap, dailySpendUsedUnits);
  const reservationUnits = compiled.actions
    .filter((action) => action.actionType === 'BUY')
    .reduce((total, action) => total + ((action.quantityUnits * action.limitPriceUnits + 500_000n) / 1_000_000n), 0n);
  const remainingUnits = capUnits > dailySpendUsedUnits ? capUnits - dailySpendUsedUnits : 0n;
  return {
    ok: true,
    evaluatedAt: { gameDay: clock.gameDay, gameMinute: clock.gameMinute },
    actions: compiled.actions.map((action) => ({
      actionType: action.actionType, product: action.product, side: action.side,
      quantity: unitsToDisplayQuantity(action.quantityUnits),
      limitPrice: priceUnitsToDisplayPrice(action.limitPriceUnits),
      maximumCreditReservation: centsToMoney((action.quantityUnits * action.limitPriceUnits + 500_000n) / 1_000_000n),
      reasonCode: action.reasonCode,
      reason: action.reason,
    })),
    maximumCreditReservation: centsToMoney(reservationUnits),
    spendCapConsumption: {
      configured: centsToMoney(capUnits),
      usedBefore: centsToMoney(dailySpendUsedUnits),
      preview: centsToMoney(reservationUnits),
      remainingAfter: centsToMoney(remainingUnits > reservationUnits ? remainingUnits - reservationUnits : 0n),
    },
    blockers: compiled.exceptions.map((exception) => ({ ...exception, reasonCode: exception.reasonCode })),
    noActionReasons: disabled
      ? ['Automation is disabled in this configuration.']
      : (compiled.actions.length === 0 && compiled.exceptions.length === 0
        ? ['No reserve shortfall or sell-above excess requires an automated market action.']
        : []),
  };
}

export async function saveHousePolicy(repository: PostgresRepository, houseId: string, input: PolicyInput): Promise<Record<string, unknown>> {
  if (!['OPERATING', 'INVENTORY_RESERVE', 'MARKET_STANDING'].includes(input.policyType)) throw new Error('Unknown policy type');
  if (!Number.isInteger(input.effectiveFromGameDay) || input.effectiveFromGameDay < 1) throw new Error('Policy effective day must be a positive integer');
  const cap = parseCreditAmount(input.dailySpendCap ?? '0').toString();
  return repository.transaction(async (tx) => {
    const replay = await tx.query('SELECT id, version, effective_from_game_day, status FROM house_operating_policies WHERE correlation_id = $1 AND house_id = $2', [input.correlationId, houseId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, policy: replay.rows[0], correlationId: input.correlationId };
    const prior = await tx.query<{ version: number }>('SELECT version FROM house_operating_policies WHERE house_id = $1 AND policy_type = $2 ORDER BY version DESC LIMIT 1 FOR UPDATE', [houseId, input.policyType]);
    const version = Number(prior.rows[0]?.version ?? 0) + 1;
    const id = `policy:${houseId}:${input.policyType}:${version}`;
    // Keep the current policy active until the scheduled replacement becomes
    // effective. The evaluator selects the latest effective version for the
    // game day, so saving a change cannot create an execution gap.
    const result = await tx.query(`INSERT INTO house_operating_policies (id, house_id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version, correlation_id) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8::JSONB,$9::JSONB,$10::JSONB,$11::JSONB,'policies-v1',$12) RETURNING id, version, effective_from_game_day, status`, [id, houseId, input.policyType, version, input.effectiveFromGameDay, input.operatingMode ?? 'BALANCED', cap, JSON.stringify(decimalMap(input.minimumReserve, 1_000_000n, 6, 'minimumReserve')), JSON.stringify(decimalMap(input.maxInputPrice, 100n, 2, 'maxInputPrice', true)), JSON.stringify(decimalMap(input.minSalePrice, 100n, 2, 'minSalePrice', true)), JSON.stringify(decimalMap(input.maxBuyQuantity, 1_000_000n, 6, 'maxBuyQuantity')), input.correlationId]);
    return { ok: true, policy: result.rows[0], correlationId: input.correlationId };
  });
}

/** Save the player-facing automation document as one scheduled configuration. */
export async function saveHouseAutomation(repository: PostgresRepository, houseId: string, input: HouseAutomationInput): Promise<Record<string, unknown>> {
  const cap = parseCreditAmount(input.dailySpendCap ?? '0').toString();
  const maps = normalizedPolicyMaps(input);
  const saved = await repository.transaction(async (tx) => {
    const clock = await readAuthoritativeGameTime(tx);
    const effectiveFromGameDay = input.effectiveFromGameDay ?? clock.gameDay + 1;
    if (!Number.isInteger(effectiveFromGameDay) || effectiveFromGameDay <= clock.gameDay) {
      throw new Error(`Automation effective day must be after the current authoritative day (${clock.gameDay})`);
    }
    const existing = await tx.query('SELECT id, version, effective_from_game_day, status FROM house_automation_versions WHERE house_id = $1 AND correlation_id = $2 LIMIT 1', [houseId, input.correlationId]);
    if (existing.rows[0]) return { ok: true, alreadyProcessed: true, policies: existing.rows, correlationId: input.correlationId };
    const prior = await tx.query<{ version: number }>('SELECT version FROM house_automation_versions WHERE house_id = $1 ORDER BY version DESC LIMIT 1 FOR UPDATE', [houseId]);
    const version = Number(prior.rows[0]?.version ?? 0) + 1;
    const id = `automation:${houseId}:${version}`;
    const result = await tx.query(`INSERT INTO house_automation_versions (id, house_id, version, effective_from_game_day, status, enabled, operating_mode, daily_spend_cap_units, minimum_reserve_units, sell_above_units, max_input_price_units, min_sale_price_units, max_buy_quantity_units, max_sell_quantity_units, rules_version, correlation_id) VALUES ($1,$2,$3,$4,'ACTIVE',$5,'BALANCED',$6,$7::JSONB,$8::JSONB,$9::JSONB,$10::JSONB,$11::JSONB,$12::JSONB,'automation-v1',$13) RETURNING id, version, effective_from_game_day, status, enabled`, [id, houseId, version, effectiveFromGameDay, input.enabled !== false, cap, JSON.stringify(maps.minimumReserve), JSON.stringify(maps.sellAbove), JSON.stringify(maps.maxInputPrice), JSON.stringify(maps.minSalePrice), JSON.stringify(maps.maxBuyQuantity), JSON.stringify(maps.maxSellQuantity), input.correlationId]);
    return { ok: true, automation: result.rows[0], effectiveFromGameDay, correlationId: input.correlationId };
  });
  const resolved = await getHouseAutomation(repository, houseId);
  return { ...saved, ...resolved };
}
