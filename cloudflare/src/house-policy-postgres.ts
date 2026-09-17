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

/** Read model for the single player-facing automation configuration. */
export async function getHouseAutomation(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  const day = Number((await repository.query<{ game_day: string }>(
    "SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'",
  )).rows[0]?.game_day ?? 1);
  const [policies, history] = await Promise.all([
    repository.query(`SELECT id, policy_type, version, effective_from_game_day, status, operating_mode,
             daily_spend_cap_units::TEXT, reserve_floor_units, max_input_price_units,
             min_sale_price_units, procurement_quantity_units, rules_version
        FROM house_operating_policies
       WHERE house_id = $1 AND status = 'ACTIVE'
       ORDER BY effective_from_game_day ASC, policy_type ASC, version DESC`, [houseId]),
    repository.query(`SELECT l.id, l.game_day, l.action_type, l.decision, l.created_at
        FROM policy_execution_log l
        WHERE l.house_id = $1
        ORDER BY l.game_day DESC, l.id DESC
        LIMIT 50`, [houseId]),
  ]);
  const current = policies.rows.filter((row) => Number(row.effective_from_game_day) <= day);
  const scheduled = policies.rows.filter((row) => Number(row.effective_from_game_day) > day);
  return {
    ok: true,
    enabled: current.length > 0,
    current,
    scheduled,
    nextRunGameDay: current.length > 0 ? day + 1 : null,
    executionHistory: history.rows,
    generatedFrom: 'postgres-canonical-facts',
  };
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
    // Keep the current policy active until the scheduled replacement becomes
    // effective. The evaluator selects the latest effective version for the
    // game day, so saving a change cannot create an execution gap.
    const result = await tx.query(`INSERT INTO house_operating_policies (id, house_id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version, correlation_id) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8::JSONB,$9::JSONB,$10::JSONB,$11::JSONB,'policies-v1',$12) RETURNING id, version, effective_from_game_day, status`, [id, houseId, input.policyType, version, input.effectiveFromGameDay, input.operatingMode ?? 'BALANCED', cap, JSON.stringify(unitMap(input.reserveFloorUnits)), JSON.stringify(unitMap(input.maxInputPriceUnits)), JSON.stringify(unitMap(input.minSalePriceUnits)), JSON.stringify(unitMap(input.procurementQuantityUnits)), input.correlationId]);
    return { ok: true, policy: result.rows[0], correlationId: input.correlationId };
  });
}

/** Save the player-facing automation document as one scheduled configuration. */
export async function saveHouseAutomation(repository: PostgresRepository, houseId: string, input: Omit<PolicyInput, 'policyType'>): Promise<Record<string, unknown>> {
  if (!Number.isInteger(input.effectiveFromGameDay) || input.effectiveFromGameDay < 1) throw new Error('Policy effective day must be a positive integer');
  const cap = String(input.dailySpendCapUnits ?? '0');
  if (!/^\d+$/.test(cap)) throw new Error('Policy spend cap must be a non-negative integer');
  return repository.transaction(async (tx) => {
    const existing = await tx.query('SELECT id, version, effective_from_game_day, status, policy_type FROM house_operating_policies WHERE house_id = $1 AND correlation_id LIKE $2 LIMIT 1', [houseId, `${input.correlationId}:automation:%`]);
    if (existing.rows[0]) return { ok: true, alreadyProcessed: true, policies: existing.rows, correlationId: input.correlationId };
    const policies: unknown[] = [];
    for (const policyType of ['OPERATING', 'INVENTORY_RESERVE', 'MARKET_STANDING'] as const) {
      const prior = await tx.query<{ version: number }>('SELECT version FROM house_operating_policies WHERE house_id = $1 AND policy_type = $2 ORDER BY version DESC LIMIT 1 FOR UPDATE', [houseId, policyType]);
      const version = Number(prior.rows[0]?.version ?? 0) + 1;
      const id = `policy:${houseId}:${policyType}:${version}`;
      const result = await tx.query(`INSERT INTO house_operating_policies (id, house_id, policy_type, version, effective_from_game_day, status, operating_mode, daily_spend_cap_units, reserve_floor_units, max_input_price_units, min_sale_price_units, procurement_quantity_units, rules_version, correlation_id) VALUES ($1,$2,$3,$4,$5,'ACTIVE',$6,$7,$8::JSONB,$9::JSONB,$10::JSONB,$11::JSONB,'policies-v1',$12) RETURNING id, version, effective_from_game_day, status, policy_type`, [id, houseId, policyType, version, input.effectiveFromGameDay, input.operatingMode ?? 'BALANCED', cap, JSON.stringify(unitMap(input.reserveFloorUnits)), JSON.stringify(unitMap(input.maxInputPriceUnits)), JSON.stringify(unitMap(input.minSalePriceUnits)), JSON.stringify(unitMap(input.procurementQuantityUnits)), `${input.correlationId}:automation:${policyType}`]);
      policies.push(result.rows[0]);
    }
    return { ok: true, policies, effectiveFromGameDay: input.effectiveFromGameDay, correlationId: input.correlationId };
  });
}
