import type { PostgresRepository } from './repository.ts';
import { BUILDING_SETTLEMENT_PIPELINE } from './building-settlement-pipeline.ts';
export { BUILDING_SETTLEMENT_PIPELINE };

type Account = { owner_id: string; economic_id: string; account_id: string; asset_id: number; account_type: number; balance: string };
type Building = { id: string; owner_id: string | null; city_id: string | null; ownership_class: string | null; resource_output_type: string | null; operating_policy: string | null; upkeep_energy: string; upkeep_food: string; upkeep_materials: string; upkeep_components: string; upkeep_compute: string; daily_operating_credits: string; output_energy: string; output_food: string; output_materials: string; output_components: string; output_compute: string; economic_output_multiplier: string | null; economic_cost_multiplier: string | null; technology_modifiers: Record<string, number> | null; technology_source_breakdown: Array<Record<string, unknown>> | null; private_owner_id: string | null };
type Effect = { ownerEconomicId: string; shard: number; accountId: string; assetId: number; delta: bigint; reasonCode: string; sourceId: string };

const ASSET_IDS: Record<string, number> = { CREDIT: 1, MATERIAL: 2, COMPONENTS: 3, ENERGY: 4, COMPUTE: 5, FOOD: 6 };
const SCALES: Record<number, number> = { 1: 100, 2: 1_000_000, 3: 1_000_000, 4: 1_000_000, 5: 1_000_000, 6: 1_000_000 };
const RESOURCE_ASSETS: Record<string, number> = { energy: 4, food: 6, materials: 2, components: 3, compute: 5 };
const units = (value: number, assetId: number) => BigInt(Math.round(value * SCALES[assetId]));
const key = (owner: string, asset: number) => `${owner}:${asset}`;

function addEffect(effects: Effect[], account: Account | undefined, delta: bigint, reasonCode: string, sourceId: string): void {
  if (delta === 0n) return;
  if (!account) throw new Error(`Missing V2 economic account for ${reasonCode} (${sourceId})`);
  effects.push({ ownerEconomicId: account.economic_id, shard: Number(BigInt(account.economic_id) % 64n), accountId: account.account_id, assetId: account.asset_id, delta, reasonCode, sourceId });
}

async function insertEffects(tx: PostgresRepository, day: number, effects: Effect[]): Promise<void> {
  if (!effects.length) return;
  const values: unknown[] = [];
  const rows = effects.map((e) => { const n = values.length; values.push(day, e.shard, e.ownerEconomicId, e.accountId, e.assetId, e.delta.toString(), e.reasonCode, e.sourceId); return `($${n + 1}, 'building_settlement', $${n + 2}, $${n + 3}, $${n + 4}, $${n + 5}, $${n + 6}, $${n + 7}, $${n + 8})`; });
  await tx.query(`INSERT INTO settlement_effects (game_day, phase, shard, owner_economic_id, account_id, asset_id, delta, reason_code, source_id) VALUES ${rows.join(',')}`, values);
}

/** Building V2 operation: inputs and explicit operating costs only. */
export async function settleBuildingUpkeepAndRevenueV2(tx: PostgresRepository, day: number): Promise<void> {
  const buildings = await tx.query<Building>(`SELECT b.id, b.owner_id, b.city_id, b.ownership_class, b.operating_policy, b.resource_output_type,
      COALESCE(bc.upkeep_energy, b.upkeep_energy, 0) AS upkeep_energy, COALESCE(bc.upkeep_food, b.upkeep_food, 0) AS upkeep_food,
      COALESCE(bc.upkeep_materials, b.upkeep_materials, 0) AS upkeep_materials, COALESCE(bc.upkeep_components, b.upkeep_components, 0) AS upkeep_components,
      COALESCE(bc.upkeep_compute, b.upkeep_compute, 0) AS upkeep_compute, COALESCE(bc.operating_credits, b.daily_operating_credits, 0) AS daily_operating_credits,
      COALESCE(bc.output_energy, 0) AS output_energy, COALESCE(bc.output_food, 0) AS output_food, COALESCE(bc.output_materials, 0) AS output_materials,
      COALESCE(bc.output_components, 0) AS output_components, COALESCE(bc.output_compute, 0) AS output_compute,
      (SELECT MAX(e.effective_output_multiplier)::NUMERIC FROM earth_calculate_building_economics(b.id) e) AS economic_output_multiplier,
      (SELECT MAX(e.effective_cost_multiplier)::NUMERIC FROM earth_calculate_building_economics(b.id) e) AS economic_cost_multiplier,
      COALESCE(cache.scoped_modifiers, '{}'::JSONB) AS technology_modifiers,
      COALESCE((SELECT owner.id FROM owner_registry owner WHERE owner.economic_id = b.owner_economic_id), (SELECT house_id FROM humans WHERE id = b.owner_id)) AS private_owner_id,
      COALESCE(cache.technology_source_breakdown, '[]'::JSONB) AS technology_source_breakdown
    FROM buildings b LEFT JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    LEFT JOIN corporation_technology_modifier_cache cache ON cache.corporation_economic_id = earth_building_corporation_economic_id(b.id) AND cache.game_day = $1
    WHERE b.status = 'active' ORDER BY b.id`, [day]);
  const ownerIds = [...new Set(buildings.rows.flatMap((b) => [b.owner_id, b.city_id]).filter((id): id is string => Boolean(id)))];
  const accountsResult = await tx.query<Account>(`SELECT o.id AS owner_id, o.economic_id::TEXT AS economic_id, a.id::TEXT AS account_id, a.asset_id, a.account_type, a.balance::TEXT
    FROM owner_registry o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
    WHERE (o.id = ANY($1::TEXT[]) OR o.id IN (SELECT house_id FROM humans WHERE id = ANY($1::TEXT[])) OR o.id = 'SYSTEM') AND a.status = 'active'`, [ownerIds]);
  const accounts = new Map<string, Account>(); const system = new Map<string, Account>(); const available = new Map<string, number>();
  for (const a of accountsResult.rows) { if ([1, 2, 3, 4, 5].includes(a.account_type)) { accounts.set(key(a.owner_id, a.asset_id), a); available.set(key(a.owner_id, a.asset_id), Number(a.balance) / SCALES[a.asset_id]); } if (a.owner_id === 'SYSTEM') system.set(`${a.asset_id}:${a.account_type}`, a); }
  const effects: Effect[] = [];
  for (const b of buildings.rows) {
    const owner = (b.ownership_class ?? 'private').toLowerCase() === 'civic' ? b.city_id : (b.private_owner_id ?? b.owner_id); if (!owner) continue;
    const costMultiplier = Math.max(0, Number(b.economic_cost_multiplier ?? 1)); const outputMultiplier = Math.max(0, Number(b.economic_output_multiplier ?? 1)); const mods = b.technology_modifiers ?? {};
    const modifier = (type: string, target: string) => Number(mods[`${type}:ASSET:${target}`] ?? mods[`${type}:ASSET:ALL`] ?? mods[`${type}:ALL_BUILDINGS:ALL`] ?? 0);
    const inputMultiplier = (asset: string) => Math.max(0, 10000 + modifier('RESOURCE_INPUT', asset) + (asset === 'ENERGY' ? modifier('ENERGY_INPUT', 'ALL') : 0)) / 10000;
    const upkeep: Record<string, number> = { energy: Number(b.upkeep_energy) * costMultiplier * inputMultiplier('ENERGY'), food: Number(b.upkeep_food) * costMultiplier * inputMultiplier('FOOD'), materials: Number(b.upkeep_materials) * costMultiplier * inputMultiplier('MATERIAL'), components: Number(b.upkeep_components) * costMultiplier * inputMultiplier('COMPONENTS'), compute: Number(b.upkeep_compute) * costMultiplier * inputMultiplier('COMPUTE') };
    // The catalog's ordinary operating cost includes maintenance. It is paid
    // as one economic expense; there is no separate maintenance or repair debt.
    const effectiveOperatingCost = Number(b.daily_operating_credits) * costMultiplier;
    const canOperate = Object.entries(upkeep).every(([n, amount]) => (available.get(key(owner, RESOURCE_ASSETS[n])) ?? 0) >= amount) && (available.get(key(owner, 1)) ?? 0) >= effectiveOperatingCost;
    const output: Record<string, number> = {}; const credit = accounts.get(key(owner, 1)); const opCost = canOperate ? effectiveOperatingCost : 0;
    if (canOperate) {
      for (const [name, value] of Object.entries({ ENERGY: b.output_energy, FOOD: b.output_food, MATERIAL: b.output_materials, COMPONENTS: b.output_components, COMPUTE: b.output_compute })) { const amount = Number(value ?? 0) * outputMultiplier * Math.max(0, 10000 + modifier('PRODUCTION_OUTPUT', name)) / 10000; if (amount > 0) output[name] = amount; }
      for (const [n, amount] of Object.entries(upkeep)) { const asset = RESOURCE_ASSETS[n]; available.set(key(owner, asset), (available.get(key(owner, asset)) ?? 0) - amount); addEffect(effects, accounts.get(key(owner, asset)), -units(amount, asset), 'building_physical_upkeep', b.id); addEffect(effects, system.get(`${asset}:8`), units(amount, asset), 'building_physical_consumption', b.id); }
      if (opCost > 0) { available.set(key(owner, 1), (available.get(key(owner, 1)) ?? 0) - opCost); addEffect(effects, credit, -units(opCost, 1), 'building_operating_cost', b.id); addEffect(effects, accounts.get(key(b.city_id ?? 'SYSTEM', 1)) ?? system.get('1:8'), units(opCost, 1), 'building_operating_revenue', b.id); }
      for (const [name, amount] of Object.entries(output)) { const asset = ASSET_IDS[name]; addEffect(effects, system.get(`${asset}:7`), -units(amount, asset), 'building_output_issuance', b.id); addEffect(effects, accounts.get(key(owner, asset)), units(amount, asset), 'building_output', b.id); }
    }
    await tx.query(`INSERT INTO building_settlement_journals (id, building_id, city_id, day, ownership_class, gross_revenue_crd, operating_costs_crd, net_surplus_crd, technology_effects) VALUES ($1,$2,$3,$4,$5,0,$6,$7,$8) ON CONFLICT (building_id, day) DO UPDATE SET operating_costs_crd=EXCLUDED.operating_costs_crd, net_surplus_crd=EXCLUDED.net_surplus_crd, technology_effects=EXCLUDED.technology_effects`, [`JOURNAL-${b.id}-${day}`, b.id, b.city_id, day, (b.ownership_class ?? 'private').toLowerCase(), opCost, -opCost, JSON.stringify({ canOperate, production: output, technologySources: b.technology_source_breakdown ?? [] })]);
  }
  await insertEffects(tx, day, effects);
}
