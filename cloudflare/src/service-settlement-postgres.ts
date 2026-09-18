import type { PostgresRepository } from './repository.ts';
import { applyConditionStack } from './world-conditions.ts';
import { postSettlementTransaction } from './economic-transaction-postgres.ts';

type NeedRule = { need_code: string; service_type_code: string; demand_units_per_human: string; critical_threshold_bps: number; rules_version: string };
type House = { house_id: string; economic_id: string; territory_id: string; residents: string };
type Provider = { territory_id: string; service_code: string; economic_id: string; owner_type: string; capacity_units: string };
type WorldCondition = { scope_type: string; scope_id: string | null; effect_type: string; target_key: string; modifier_bps: number };

const SERVICE_CODES = ['CONNECTIVITY', 'HEALTH'];

function units(value: unknown): bigint {
  const text = String(value ?? '0');
  if (!/^\d+$/.test(text)) throw new Error('Service settlement received a non-integer unit value');
  return BigInt(text);
}

function risk(allocated: bigint, demand: bigint, thresholdBps: number): 'NORMAL' | 'WATCH' | 'CRITICAL' {
  if (demand === 0n || allocated * 10000n >= demand * BigInt(thresholdBps)) return 'NORMAL';
  if (allocated > 0n) return 'WATCH';
  return 'CRITICAL';
}

async function account(tx: PostgresRepository, economicId: string, purpose: string): Promise<{ id: string; balance_units: string } | null> {
  const result = await tx.query<{ id: string; balance_units: string }>(
    `SELECT a.id::TEXT AS id, a.balance_units::TEXT AS balance_units
       FROM economic_accounts a
       JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      WHERE a.owner_economic_id = $1 AND a.asset_id = 1 AND a.account_type = $2 AND a.status = 'ACTIVE'
      FOR UPDATE`, [economicId, purpose],
  );
  return result.rows[0] ?? null;
}

async function payService(tx: PostgresRepository, day: number, house: House, provider: Provider, serviceCode: string, amount: bigint, pricePerUnit: bigint): Promise<string | null> {
  const total = amount * pricePerUnit;
  if (total === 0n || provider.economic_id === house.economic_id) return null;
  const payer = await account(tx, house.economic_id, 'WALLET');
  const providerAccount = await account(tx, provider.economic_id, provider.owner_type === 'CORPORATION' ? 'OPERATIONS' : 'WALLET');
  if (!payer || !providerAccount || units(payer.balance_units) < total) return null;
  const result = await postSettlementTransaction(tx, {
    correlationId: `service:${day}:${house.house_id}:${serviceCode}:${provider.economic_id}`,
    gameDay: day,
    kind: 'ASSET_TRANSFER',
    sourceType: 'SYSTEM_SETTLEMENT',
    sourceId: serviceCode,
    rulesVersion: 'services-v1',
    entries: [
      { accountId: payer.id, assetId: 1, deltaUnits: (-total).toString(), reasonCode: 'house_service_payment' },
      { accountId: providerAccount.id, assetId: 1, deltaUnits: total.toString(), reasonCode: 'house_service_revenue' },
    ],
  });
  return result.transactionId ?? null;
}

async function createServiceObligation(tx: PostgresRepository, day: number, house: House, provider: Provider, serviceCode: string, amount: bigint): Promise<void> {
  if (amount <= 0n || provider.economic_id === house.economic_id) return;
  const id = `service-obligation:${day}:${house.house_id}:${serviceCode}:${provider.economic_id}`;
  await tx.query(`INSERT INTO financial_obligations (id, debtor_economic_id, creditor_economic_id, obligation_type, source_id, principal_due_units, due_game_day, priority_class, rule_version, created_game_day, correlation_id) VALUES ($1,$2,$3,'SERVICE_INVOICE',$4,$5,$6,40,'services-v1',$6,$1) ON CONFLICT (correlation_id) DO NOTHING`, [id, house.economic_id, provider.economic_id, serviceCode, amount.toString(), day]);
}

// @mutation-boundary caller-owned-transaction: needs and service settlement is an owner-sharded phase transaction.
export async function settleHouseNeedsAndServices(tx: PostgresRepository, day: number, shard = 0, shardCount = 16): Promise<{ houses: number; allocations: number; shortfalls: number }> {
  const [rulesResult, housesResult] = await Promise.all([
    tx.query<NeedRule>(`SELECT need_code, service_type_code, demand_units_per_human::TEXT, critical_threshold_bps, rules_version FROM need_rules WHERE status = 'ACTIVE' ORDER BY need_code`),
    tx.query<House>(`SELECT h.id AS house_id, owner.economic_id, r.territory_id,
            COUNT(human.id)::TEXT AS residents
       FROM houses h JOIN owner_registry owner ON owner.id = h.id AND owner.owner_type = 'HOUSE'
       JOIN house_residencies r ON r.house_id = h.id AND r.status = 'ACTIVE' AND r.residency_class = 'PRIMARY'
       LEFT JOIN humans human ON human.house_id = h.id AND human.status = 'ACTIVE'
      WHERE mod(abs(hashtextextended(h.id, 0)), $1) = $2
      GROUP BY h.id, owner.economic_id, r.territory_id ORDER BY h.id`, [shardCount, shard]),
  ]);
  const rules = rulesResult.rows;
  const houses = housesResult.rows;
  const conditions = (await tx.query<WorldCondition>(`SELECT scope_type, scope_id, effect_type, target_key, modifier_bps
    FROM world_conditions
   WHERE effective_from_game_day <= $1 AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
     AND effect_type IN ('DEMAND_MULTIPLIER', 'CAPACITY_MULTIPLIER')
   ORDER BY scope_type, scope_id NULLS FIRST, target_key, id`, [day])).rows;
  const organizationRows = (await tx.query<{ economic_id: string; organization_id: string }>('SELECT economic_id, organization_id FROM organization_economies')).rows;
  const organizationByEconomic = new Map(organizationRows.map((row) => [row.economic_id, row.organization_id]));
  const modifiersFor = (effectType: string, target: string, territoryId: string | null, economicId?: string): number[] => conditions
    .filter((condition) => condition.effect_type === effectType && (condition.target_key === target || condition.target_key === '*'))
    .filter((condition) => condition.scope_type === 'WORLD' || (condition.scope_type === 'TERRITORY' && condition.scope_id === territoryId) || (condition.scope_type === 'ORGANIZATION' && condition.scope_id === organizationByEconomic.get(economicId ?? '')))
    .map((condition) => Number(condition.modifier_bps));
  const prices = new Map<string, bigint>();
  for (const row of (await tx.query<{ code: string; daily_price_units: string }>(`SELECT code, daily_price_units::TEXT FROM service_types WHERE status = 'ACTIVE'`)).rows) prices.set(row.code, units(row.daily_price_units));
  const providerMap = new Map<string, Provider[]>();
  const providerRows = await tx.query<Provider>(`SELECT b.territory_id, c.service_type AS service_code, b.owner_economic_id AS economic_id, owner.owner_type, SUM(c.service_capacity_units)::TEXT AS capacity_units
     FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id
    WHERE b.status = 'ACTIVE' AND c.economic_role IN ('SERVICE', 'INFRASTRUCTURE') AND c.service_type = ANY($1)
    GROUP BY b.territory_id, c.service_type, b.owner_economic_id, owner.owner_type ORDER BY b.territory_id, c.service_type, b.owner_economic_id`, [SERVICE_CODES]);
  for (const provider of providerRows.rows) {
    const key = `${provider.territory_id}:${provider.service_code}`;
    const adjusted = { ...provider, capacity_units: applyConditionStack(units(provider.capacity_units), modifiersFor('CAPACITY_MULTIPLIER', provider.service_code, provider.territory_id, provider.economic_id)).toString() };
    providerMap.set(key, [...(providerMap.get(key) ?? []), adjusted]);
  }
  const remainingCapacity = new Map<string, bigint>();
  for (const providers of providerMap.values()) {
    for (const provider of providers) {
      remainingCapacity.set(`${provider.territory_id}:${provider.service_code}:${provider.economic_id}`, units(provider.capacity_units));
    }
  }
  type HouseDemandState = {
    house: House;
    rule: NeedRule;
    demand: bigint;
    remaining: bigint;
    allocated: bigint;
    availableCapacity: bigint;
  };

  const houseStates: HouseDemandState[] = [];

  for (const house of houses) {
    const residentDemand = units(house.residents);
    for (const rule of rules) {
      if (!SERVICE_CODES.includes(rule.service_type_code)) continue;
      const prior = await tx.query(`SELECT 1 FROM house_need_assessments WHERE house_id = $1 AND game_day = $2 AND need_code = $3`, [house.house_id, day, rule.need_code]);
      if (prior.rows[0]) continue;
      const demand = applyConditionStack(residentDemand * units(rule.demand_units_per_human), modifiersFor('DEMAND_MULTIPLIER', rule.service_type_code, house.territory_id));
      const providerRows = providerMap.get(`${house.territory_id}:${rule.service_type_code}`) ?? [];
      const availableCapacity = providerRows.reduce((sum, provider) => sum + (remainingCapacity.get(`${provider.territory_id}:${provider.service_code}:${provider.economic_id}`) ?? 0n), 0n);
      houseStates.push({
        house,
        rule,
        demand,
        remaining: demand,
        allocated: 0n,
        availableCapacity,
      });
    }
  }

  let allocations = 0; let shortfalls = 0;

  // Pass 1: Self-provisioning (Houses consume from their own facilities in the territory first at 0 fee)
  for (const state of houseStates) {
    if (state.remaining <= 0n) continue;
    const providerKey = `${state.house.territory_id}:${state.rule.service_type_code}:${state.house.economic_id}`;
    const available = remainingCapacity.get(providerKey) ?? 0n;
    if (available <= 0n) continue;
    const candidate = available < state.remaining ? available : state.remaining;
    await tx.query(`INSERT INTO service_allocations (id, house_id, territory_id, service_code, provider_economic_id, payer_economic_id, game_day, capacity_units, allocated_units, price_units, economic_transaction_id, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (house_id, service_code, game_day, provider_economic_id) DO NOTHING`, [`service:${day}:${state.house.house_id}:${state.rule.service_type_code}:${state.house.economic_id}`, state.house.house_id, state.house.territory_id, state.rule.service_type_code, state.house.economic_id, state.house.economic_id, day, available.toString(), candidate.toString(), '0', null, `service:${day}:${state.house.house_id}:${state.rule.service_type_code}:${state.house.economic_id}`]);
    remainingCapacity.set(providerKey, available - candidate);
    state.allocated += candidate;
    state.remaining -= candidate;
    allocations += 1;
  }

  // Pass 2: Market & Public provision (Private providers first, Corporation public infrastructure next)
  for (const state of houseStates) {
    if (state.remaining > 0n) {
      const rawProviders = providerMap.get(`${state.house.territory_id}:${state.rule.service_type_code}`) ?? [];
      const externalProviders = rawProviders
        .filter((p) => p.economic_id !== state.house.economic_id)
        .sort((a, b) => {
          const aPrivate = a.owner_type === 'HOUSE' ? 0 : 1;
          const bPrivate = b.owner_type === 'HOUSE' ? 0 : 1;
          if (aPrivate !== bPrivate) return aPrivate - bPrivate;
          return a.economic_id.localeCompare(b.economic_id);
        });

      for (const provider of externalProviders) {
        if (state.remaining <= 0n) break;
        const providerKey = `${provider.territory_id}:${provider.service_code}:${provider.economic_id}`;
        const available = remainingCapacity.get(providerKey) ?? 0n;
        if (available <= 0n) continue;
        const candidate = available < state.remaining ? available : state.remaining;
        const price = prices.get(state.rule.service_type_code) ?? 0n;
        const transactionId = await payService(tx, day, state.house, provider, state.rule.service_type_code, candidate, price);
        if (price > 0n && !transactionId) await createServiceObligation(tx, day, state.house, provider, state.rule.service_type_code, candidate * price);
        const allocation = candidate;
        await tx.query(`INSERT INTO service_allocations (id, house_id, territory_id, service_code, provider_economic_id, payer_economic_id, game_day, capacity_units, allocated_units, price_units, economic_transaction_id, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (house_id, service_code, game_day, provider_economic_id) DO NOTHING`, [`service:${day}:${state.house.house_id}:${state.rule.service_type_code}:${provider.economic_id}`, state.house.house_id, state.house.territory_id, state.rule.service_type_code, provider.economic_id, state.house.economic_id, day, available.toString(), allocation.toString(), (allocation * price).toString(), transactionId, `service:${day}:${state.house.house_id}:${state.rule.service_type_code}:${provider.economic_id}`]);
        remainingCapacity.set(providerKey, available - allocation);
        state.allocated += allocation;
        state.remaining -= allocation;
        allocations += 1;
      }
    }

    const shortfall = state.demand - state.allocated;
    if (shortfall > 0n) shortfalls += 1;
    await tx.query(`INSERT INTO house_need_assessments (house_id, game_day, need_code, demand_units, available_units, allocated_units, shortfall_units, risk_level, rules_version) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT (house_id, game_day, need_code) DO UPDATE SET demand_units = EXCLUDED.demand_units, available_units = EXCLUDED.available_units, allocated_units = EXCLUDED.allocated_units, shortfall_units = EXCLUDED.shortfall_units, risk_level = EXCLUDED.risk_level, rules_version = EXCLUDED.rules_version, updated_at = CURRENT_TIMESTAMP`, [state.house.house_id, day, state.rule.need_code, state.demand.toString(), state.availableCapacity.toString(), state.allocated.toString(), shortfall.toString(), risk(state.allocated, state.demand, state.rule.critical_threshold_bps), state.rule.rules_version]);
  }
  return { houses: houses.length, allocations, shortfalls };
}
