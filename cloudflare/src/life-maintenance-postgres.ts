import type { PostgresRepository } from './repository.ts';

const FOOD_ASSET_ID = 6;
const FOOD_REQUIRED_PER_HUMAN = 1n;
const FOOD_CONSUMPTION_OWNER = 'ECON-RESOURCE-CONSUMPTION';

export type LifeMaintenanceEstimate = { dailyCredits: number; resources: Record<string, number> };

export function estimateLifeMaintenance(): LifeMaintenanceEstimate {
  return { dailyCredits: 0, resources: { FOOD: Number(FOOD_REQUIRED_PER_HUMAN) } };
}

type MaintenanceHuman = { id: string; house_id: string; economic_id: string; account_id: string; balance_units: string };

// @mutation-boundary deterministic-settlement: the finalized day is the retry key for maintenance charges.
export async function settleLifeMaintenanceInTransaction(tx: PostgresRepository, day: number): Promise<number> {
  const humans = await tx.query<MaintenanceHuman>(
    `SELECT h.id, h.house_id, owner.economic_id,
            inventory.id::TEXT AS account_id, inventory.balance_units::TEXT AS balance_units
       FROM humans h
       JOIN owner_registry owner ON owner.id = h.house_id AND owner.owner_type = 'HOUSE'
       JOIN economic_accounts inventory
         ON inventory.owner_economic_id = owner.economic_id
        AND inventory.asset_id = $1
        AND inventory.account_type = 'INVENTORY'
        AND inventory.status = 'ACTIVE'
      WHERE h.status = 'ACTIVE'
      ORDER BY h.id
      FOR UPDATE OF h, inventory`, [FOOD_ASSET_ID],
  );
  const sink = (await tx.query<{ id: string }>(
    `SELECT a.id::TEXT AS id
       FROM economic_accounts a
       JOIN owner_registry owner ON owner.economic_id = a.owner_economic_id
      WHERE owner.economic_id = $1 AND a.asset_id = $2 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'
      LIMIT 1`, [FOOD_CONSUMPTION_OWNER, FOOD_ASSET_ID],
  )).rows[0];
  if (humans.rows.length && !sink) throw new Error('FOOD consumption system account is not provisioned');

  let settled = 0;
  for (const human of humans.rows) {
    const prior = (await tx.query('SELECT id FROM personal_life_maintenance WHERE human_id = $1 AND game_day = $2', [human.id, day])).rows[0];
    if (prior) continue;
    const available = BigInt(human.balance_units);
    const consumed = available < FOOD_REQUIRED_PER_HUMAN ? available : FOOD_REQUIRED_PER_HUMAN;
    const shortfall = FOOD_REQUIRED_PER_HUMAN - consumed;
    if (consumed > 0n) {
      await tx.query(
        `SELECT earth_post_transaction($1, $2, 1439, 'RESOURCE_CONSUMPTION', 'SYSTEM_CONSUMPTION', $3, 'life-maintenance-v1', $4::JSONB)`,
        [`food-maintenance:${human.id}:${day}`, day, human.id, JSON.stringify([
          { account_id: human.account_id, asset_id: FOOD_ASSET_ID, delta_units: (-consumed).toString(), reason_code: 'human_daily_food' },
          { account_id: sink.id, asset_id: FOOD_ASSET_ID, delta_units: consumed.toString(), reason_code: 'human_daily_food' },
        ])],
      );
    }
    await tx.query(
      `INSERT INTO personal_life_maintenance
        (human_id, house_id, game_day, food_required_units, food_consumed_units, food_shortfall_units, status, shortfall_notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [human.id, human.house_id, day, FOOD_REQUIRED_PER_HUMAN.toString(), consumed.toString(), shortfall.toString(), shortfall === 0n ? 'FED' : consumed === 0n ? 'UNFED' : 'PARTIAL', shortfall === 0n ? null : 'House FOOD inventory was insufficient at daily opening'],
    );
    settled += 1;
  }
  return settled;
}

export async function settleLifeMaintenance(repository: PostgresRepository, day: number): Promise<number> {
  return repository.transaction((tx) => settleLifeMaintenanceInTransaction(tx, day));
}
