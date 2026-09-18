import type { PostgresRepository } from './repository.ts';
import { postSettlementTransaction } from './economic-transaction-postgres.ts';

const FOOD_ASSET_ID = 6;
const FOOD_REQUIRED_PER_HUMAN = 1n;
const ENERGY_ASSET_ID = 4;
const ENERGY_REQUIRED_PER_HUMAN = 1n;
const CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';

export type LifeMaintenanceEstimate = { dailyCredits: number; resources: Record<string, number> };

export function estimateLifeMaintenance(): LifeMaintenanceEstimate {
  return {
    dailyCredits: 0,
    resources: {
      FOOD: Number(FOOD_REQUIRED_PER_HUMAN),
      ENERGY: Number(ENERGY_REQUIRED_PER_HUMAN),
    },
  };
}

type MaintenanceHuman = {
  id: string;
  house_id: string;
  economic_id: string;
  food_account_id: string | null;
  food_balance_units: string | null;
  energy_account_id: string | null;
  energy_balance_units: string | null;
};

// @mutation-boundary deterministic-settlement: the finalized day is the retry key for maintenance charges.
export async function settleLifeMaintenanceInTransaction(tx: PostgresRepository, day: number): Promise<number> {
  const humans = await tx.query<MaintenanceHuman>(
    `SELECT h.id, h.house_id, owner.economic_id,
            food_inv.id::TEXT AS food_account_id, food_inv.balance_units::TEXT AS food_balance_units,
            energy_inv.id::TEXT AS energy_account_id, energy_inv.balance_units::TEXT AS energy_balance_units
       FROM humans h
       JOIN owner_registry owner ON owner.id = h.house_id AND owner.owner_type = 'HOUSE'
       LEFT JOIN economic_accounts food_inv
         ON food_inv.owner_economic_id = owner.economic_id
        AND food_inv.asset_id = $1
        AND food_inv.account_type = 'INVENTORY'
        AND food_inv.status = 'ACTIVE'
       LEFT JOIN economic_accounts energy_inv
         ON energy_inv.owner_economic_id = owner.economic_id
        AND energy_inv.asset_id = $2
        AND energy_inv.account_type = 'INVENTORY'
        AND energy_inv.status = 'ACTIVE'
      WHERE h.status = 'ACTIVE'
      ORDER BY h.id
      FOR UPDATE OF h`, [FOOD_ASSET_ID, ENERGY_ASSET_ID],
  );

  const sinks = (await tx.query<{ id: string; asset_id: number }>(
    `SELECT a.id::TEXT AS id, a.asset_id
       FROM economic_accounts a
       JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
      WHERE owner.economic_id = $1
        AND a.asset_id IN ($2, $3)
        AND a.account_type = 'SYSTEM_ACCOUNT'
        AND a.status = 'ACTIVE'`, [CONSUMPTION_OWNER, FOOD_ASSET_ID, ENERGY_ASSET_ID],
  )).rows;

  const foodSink = sinks.find((s) => Number(s.asset_id) === FOOD_ASSET_ID);
  const energySink = sinks.find((s) => Number(s.asset_id) === ENERGY_ASSET_ID);

  if (humans.rows.length > 0 && !foodSink) throw new Error('FOOD consumption system account is not provisioned');
  if (humans.rows.length > 0 && !energySink) throw new Error('ENERGY consumption system account is not provisioned');

  const remainingFoodByHouse = new Map<string, bigint>();
  const remainingEnergyByHouse = new Map<string, bigint>();

  for (const human of humans.rows) {
    if (!remainingFoodByHouse.has(human.house_id)) {
      remainingFoodByHouse.set(human.house_id, BigInt(human.food_balance_units ?? '0'));
    }
    if (!remainingEnergyByHouse.has(human.house_id)) {
      remainingEnergyByHouse.set(human.house_id, BigInt(human.energy_balance_units ?? '0'));
    }
  }

  let settled = 0;
  for (const human of humans.rows) {
    const prior = (await tx.query('SELECT id FROM personal_life_maintenance WHERE human_id = $1 AND game_day = $2', [human.id, day])).rows[0];
    if (prior) continue;

    const availableFood = remainingFoodByHouse.get(human.house_id) ?? 0n;
    const consumedFood = human.food_account_id && availableFood > 0n
      ? (availableFood < FOOD_REQUIRED_PER_HUMAN ? availableFood : FOOD_REQUIRED_PER_HUMAN)
      : 0n;
    const shortfallFood = FOOD_REQUIRED_PER_HUMAN - consumedFood;
    remainingFoodByHouse.set(human.house_id, availableFood - consumedFood);

    const availableEnergy = remainingEnergyByHouse.get(human.house_id) ?? 0n;
    const consumedEnergy = human.energy_account_id && availableEnergy > 0n
      ? (availableEnergy < ENERGY_REQUIRED_PER_HUMAN ? availableEnergy : ENERGY_REQUIRED_PER_HUMAN)
      : 0n;
    const shortfallEnergy = ENERGY_REQUIRED_PER_HUMAN - consumedEnergy;
    remainingEnergyByHouse.set(human.house_id, availableEnergy - consumedEnergy);

    if (consumedFood > 0n && human.food_account_id && foodSink) {
      await postSettlementTransaction(tx, {
        correlationId: `food-maintenance:${human.id}:${day}`,
        gameDay: day,
        kind: 'RESOURCE_CONSUMPTION',
        sourceType: 'SYSTEM_CONSUMPTION',
        sourceId: human.id,
        rulesVersion: 'life-maintenance-v1',
        entries: [
          { accountId: human.food_account_id, assetId: FOOD_ASSET_ID, deltaUnits: (-consumedFood).toString(), reasonCode: 'human_daily_food' },
          { accountId: foodSink.id, assetId: FOOD_ASSET_ID, deltaUnits: consumedFood.toString(), reasonCode: 'human_daily_food' },
        ],
      });
    }

    if (consumedEnergy > 0n && human.energy_account_id && energySink) {
      await postSettlementTransaction(tx, {
        correlationId: `energy-maintenance:${human.id}:${day}`,
        gameDay: day,
        kind: 'RESOURCE_CONSUMPTION',
        sourceType: 'SYSTEM_CONSUMPTION',
        sourceId: human.id,
        rulesVersion: 'life-maintenance-v1',
        entries: [
          { accountId: human.energy_account_id, assetId: ENERGY_ASSET_ID, deltaUnits: (-consumedEnergy).toString(), reasonCode: 'human_daily_energy' },
          { accountId: energySink.id, assetId: ENERGY_ASSET_ID, deltaUnits: consumedEnergy.toString(), reasonCode: 'human_daily_energy' },
        ],
      });
    }

    const status = (shortfallFood === 0n && shortfallEnergy === 0n)
      ? 'FED'
      : (consumedFood === 0n && consumedEnergy === 0n)
        ? 'UNFED'
        : 'PARTIAL';

    const notes: string[] = [];
    if (shortfallFood > 0n) notes.push('House FOOD inventory was insufficient at daily opening');
    if (shortfallEnergy > 0n) notes.push('House ENERGY inventory was insufficient at daily opening');

    await tx.query(
      `INSERT INTO personal_life_maintenance
        (human_id, house_id, game_day, food_required_units, food_consumed_units, food_shortfall_units, energy_required_units, energy_consumed_units, energy_shortfall_units, status, shortfall_notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
      [
        human.id,
        human.house_id,
        day,
        FOOD_REQUIRED_PER_HUMAN.toString(),
        consumedFood.toString(),
        shortfallFood.toString(),
        ENERGY_REQUIRED_PER_HUMAN.toString(),
        consumedEnergy.toString(),
        shortfallEnergy.toString(),
        status,
        notes.length ? notes.join('; ') : null,
      ],
    );
    settled += 1;
  }
  return settled;
}

export async function settleLifeMaintenance(repository: PostgresRepository, day: number): Promise<number> {
  return repository.transaction((tx) => settleLifeMaintenanceInTransaction(tx, day));
}
