import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';

type Resident = {
  id: string;
  age_years: number;
  account_id: string;
  balance: string;
  city_id: string | null;
  residents: string | null;
  housing_capacity: string | null;
  energy_capacity: string | null;
  connectivity_capacity: string | null;
  health_capacity: string | null;
};

export type LifeMaintenanceEstimate = {
  food: number;
  housing: number;
  energy: number;
  health: number;
  connectivity: number;
  total: number;
};

const roundMoney = (amount: number) => Math.round(amount * 100) / 100;
const serviceCoverage = (capacity: unknown, residents: unknown) =>
  Math.max(0, Math.min(1, Number(capacity ?? 0) / Math.max(1, Number(residents ?? 1))));

export function estimateLifeMaintenance(resident: Omit<Resident, 'id' | 'account_id' | 'balance'>, livingCostIndex: number): LifeMaintenanceEstimate {
  const age = Math.max(0, Number(resident.age_years ?? 30));
  const ageFood = age < 18 ? 0.8 : age >= 75 ? 1.12 : 1;
  const ageHealth = age < 18 ? 0.85 : age >= 65 ? 1.55 : age >= 50 ? 1.2 : 1;
  const index = Math.max(0.5, Math.min(3, Number(livingCostIndex || 1)));
  const residents = resident.residents;
  const housingSupport = serviceCoverage(resident.housing_capacity, residents) * 0.3;
  const energySupport = serviceCoverage(resident.energy_capacity, residents) * 0.2;
  const connectivitySupport = serviceCoverage(resident.connectivity_capacity, residents) * 0.15;
  const healthSupport = Math.max(0, Math.min(1, Number(resident.health_capacity ?? 0) / 100)) * 0.25;
  const food = roundMoney(18 * index * ageFood);
  const housing = roundMoney(12 * index * (1 - housingSupport));
  const energy = roundMoney(5 * index * (1 - energySupport));
  const health = roundMoney(3 * index * ageHealth * (1 - healthSupport));
  const connectivity = roundMoney(2 * index * (1 - connectivitySupport));
  return { food, housing, energy, health, connectivity, total: roundMoney(food + housing + energy + health + connectivity) };
}

export async function settleLifeMaintenance(tx: PostgresRepository, day: number): Promise<number> {
  const world = await tx.query<{ living_cost_index: string }>("SELECT living_cost_index FROM world_state WHERE id = 'WORLD'");
  const residents = await tx.query<Resident>(
    "SELECT h.id, h.age_years, a.account_id, a.balance, m.city_id, c.residents, c.housing_capacity, c.energy_capacity, c.connectivity_capacity, c.health_capacity FROM humans h JOIN account_balances a ON a.owner_id = h.id AND a.currency = 'CREDIT' LEFT JOIN memberships m ON m.human_id = h.id LEFT JOIN cities c ON c.id = m.city_id WHERE h.life_status = 'active' FOR UPDATE",
  );
  let settled = 0;
  for (const resident of residents.rows) {
    const prior = await tx.query('SELECT 1 FROM personal_life_maintenance WHERE human_id = $1 AND game_day = $2', [resident.id, day]);
    if (prior.rows[0]) continue;
    const cost = estimateLifeMaintenance(resident, Number(world.rows[0]?.living_cost_index ?? 1));
    const needs = { food: 1, energy: 1, compute: 0.25 };
    const resources = await tx.query<{ resource: string; amount: string }>("SELECT resource, amount FROM resource_balances WHERE owner_id = $1 AND resource IN ('food','energy','compute') FOR UPDATE", [resident.id]);
    const prices = await tx.query<{ product: string; price: string }>("SELECT product, price FROM market_prices WHERE product IN ('food','energy','compute')");
    const balanceByResource = new Map(resources.rows.map((row) => [row.resource, Number(row.amount)]));
    const priceByResource = new Map(prices.rows.map((row) => [row.product, Number(row.price)]));
    let emergencyCost = 0;
    let missing = 0;
    const used: Record<string, number> = {};
    for (const [resource, required] of Object.entries(needs)) {
      const held = Math.max(0, balanceByResource.get(resource) ?? 0);
      const consumed = Math.min(held, required);
      used[resource] = consumed;
      if (consumed > 0) await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3', [consumed, resident.id, resource]);
      const shortage = required - consumed;
      const purchase = shortage * Math.max(0, priceByResource.get(resource) ?? 0);
      emergencyCost += purchase;
    }
    const availableCents = moneyToCents(resident.balance);
    const emergencyCents = moneyToCents(emergencyCost);
    const paidCents = availableCents < emergencyCents ? availableCents : emergencyCents;
    const unpaidCents = emergencyCents - paidCents;
    missing = emergencyCents > 0n ? Number(unpaidCents) / Number(emergencyCents) : 0;
    const correlationId = `LIFE-MAINTENANCE-${resident.id}-${day}`;
    if (paidCents > 0n) {
      await transferCredits(tx, {
        ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: resident.account_id,
        creditAccount: 'account-ouc-treasury', amount: centsToMoney(paidCents),
        reasonType: 'life_maintenance_resources', reasonId: resident.id, ruleVersion: 'life-maintenance-v2', correlationId,
      });
    }
    const status = unpaidCents === 0n ? 'settled' : paidCents === 0n ? 'deferred' : 'partially_settled';
    await tx.query(
      'INSERT INTO personal_life_maintenance (human_id,game_day,food,housing,energy,health,connectivity,total,paid,unpaid,city_id,status,food_used,energy_used,compute_used,credits_for_resources,life_condition_before,life_condition_after,shortfall_notes) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)',
      [resident.id, day, cost.food, cost.housing, cost.energy, cost.health, cost.connectivity, emergencyCost, centsToMoney(paidCents), centsToMoney(unpaidCents), resident.city_id, status, used.food, used.energy, used.compute, centsToMoney(paidCents), 100, Math.max(0, 100 - Math.ceil(missing * 15)), missing > 0 ? 'Essential resources could not be fully covered.' : ''],
    );
    await tx.query('INSERT INTO human_life_conditions (human_id,score,updated_game_day,last_reason) VALUES ($1,$2,$3,$4) ON CONFLICT (human_id) DO UPDATE SET score = $2, updated_game_day = $3, last_reason = $4', [resident.id, Math.max(0, 100 - Math.ceil(missing * 15)), day, missing > 0 ? 'resource shortfall' : 'needs covered']);
    if (unpaidCents > 0n) {
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'finance\',\'Life maintenance needs attention\',$3,$4) ON CONFLICT (id) DO NOTHING', [`LIFE-MAINTENANCE-${resident.id}-${day}`, resident.id, `${centsToMoney(unpaidCents)} Credits of today\'s essential costs could not be covered. Earn Credits or review your city services.`, correlationId]);
    }
    settled += 1;
  }
  return settled;
}
