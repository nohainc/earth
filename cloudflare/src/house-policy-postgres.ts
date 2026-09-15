import type { PostgresRepository } from './repository.ts';

type PolicyInput = {
  policyType: 'OPERATING' | 'INVENTORY_RESERVE' | 'MARKET_STANDING';
  operatingMode?: 'CONSERVATIVE' | 'BALANCED' | 'GROWTH' | 'CUSTOM';
  effectiveFromGameDay: number;
  dailySpendCapUnits?: string;
  reserveFloorUnits?: Record<string, string | number>;
  maxInputPriceUnits?: Record<string, string | number>;
  minSalePriceUnits?: Record<string, string | number>;
  procurementQuantityUnits?: Record<string, string | number>;
  correlationId: string;
};

function unitMap(value: Record<string, string | number> = {}): Record<string, string> {
  return Object.fromEntries(Object.entries(value).map(([key, raw]) => {
    const normalized = String(raw);
    if (!/^\d+$/.test(normalized)) throw new Error(`Policy unit for ${key} must be a non-negative integer`);
    return [key.toUpperCase(), normalized];
  }));
}

export async function listHousePolicies(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units::TEXT, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version FROM house_operating_policies WHERE house_id = $1 ORDER BY policy_type, version DESC`, [houseId]);
  return { policies: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function saveHousePolicy(repository: PostgresRepository, houseId: string, input: PolicyInput): Promise<Record<string, unknown>> {
  if (!['OPERATING', 'INVENTORY_RESERVE', 'MARKET_STANDING'].includes(input.policyType)) throw new Error('Unknown policy type');
  if (!Number.isInteger(input.effectiveFromGameDay) || input.effectiveFromGameDay < 1) throw new Error('Policy effective day must be a positive integer');
  const cap = String(input.dailySpendCapUnits ?? '0');
  if (!/^\d+$/.test(cap)) throw new Error('Policy spend cap must be a non-negative integer');
  return repository.transaction(async (tx) => {
    const replay = await tx.query('SELECT id, version, effective_from_game_day, status FROM house_operating_policies WHERE correlation_id = $1 AND house_id = $2', [input.correlationId, houseId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, policy: replay.rows[0], correlationId: input.correlationId };
    const prior = await tx.query<{ version: number }>('SELECT version FROM house_operating_policies WHERE house_id = $1 AND policy_type = $2 ORDER BY version DESC LIMIT 1 FOR UPDATE', [houseId, input.policyType]);
    const version = Number(prior.rows[0]?.version ?? 0) + 1;
    const id = `policy:${houseId}:${input.policyType}:${version}`;
    await tx.query(`UPDATE house_operating_policies SET status = 'SUPERSEDED', updated_at = CURRENT_TIMESTAMP WHERE house_id = $1 AND policy_type = $2 AND status = 'ACTIVE'`, [houseId, input.policyType]);
    const result = await tx.query(`INSERT INTO house_operating_policies (id, house_id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version, correlation_id) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8::JSONB,$9::JSONB,$10::JSONB,$11::JSONB,'policies-v1',$12) RETURNING id, version, effective_from_game_day, status`, [id, houseId, input.policyType, version, input.effectiveFromGameDay, input.operatingMode ?? 'BALANCED', cap, JSON.stringify(unitMap(input.reserveFloorUnits)), JSON.stringify(unitMap(input.maxInputPriceUnits)), JSON.stringify(unitMap(input.minSalePriceUnits)), JSON.stringify(unitMap(input.procurementQuantityUnits)), input.correlationId]);
    return { ok: true, policy: result.rows[0], correlationId: input.correlationId };
  });
}
