import type { PostgresRepository } from './repository.ts';

// @mutation-boundary caller-owned-transaction
// @mutation-boundary deterministic-settlement
// Reconciliation is deliberately invoked inside the scheduler's atomic settlement transaction.

/**
 * Reconciles standardized Territory containers from the v5 capacity state.
 * It never changes building or House placement; containers are accounting and
 * history records only while v5 geography remains undifferentiated.
 */
export async function reconcileV5TerritoryContainersInTransaction(tx: PostgresRepository, day: number): Promise<Record<string, unknown>> {
  const states = (await tx.query<{ corporation_id: string; required_territory_units: string; standard_territory_capacity_units: string }>(`SELECT corporation_id, required_territory_units::TEXT, standard_territory_capacity_units::TEXT
    FROM corporation_capacity_state_v5 WHERE game_day = $1 ORDER BY corporation_id`, [day])).rows;
  let created = 0;
  let retired = 0;
  for (const state of states) {
    const required = Number(state.required_territory_units);
    const containers = (await tx.query<{ id: string; v5_sequence_number: number }>(`SELECT id, v5_sequence_number FROM territories
      WHERE corporation_id = $1 AND status = 'ACTIVE' AND v5_sequence_number IS NOT NULL ORDER BY v5_sequence_number FOR UPDATE`, [state.corporation_id])).rows;
    for (let sequence = containers.length + 1; sequence <= required; sequence += 1) {
      const id = `T5-${state.corporation_id}-${sequence}`;
      await tx.query(`INSERT INTO territories
        (id, corporation_id, name, territory_type, status, is_primary, created_game_day, v5_sequence_number,
         v5_capacity_units, v5_activated_game_day, v5_rules_version)
        VALUES ($1,$2,$3,'V5_STANDARD','ACTIVE',FALSE,$4,$5,$6,$4,$7)
        ON CONFLICT (id) DO NOTHING`, [id, state.corporation_id, `Standard Capacity ${sequence}`, day, sequence, state.standard_territory_capacity_units, 'v5-capacity-policy']);
      created += 1;
    }
    if (containers.length > required) {
      const excess = containers.slice(required);
      for (const container of excess) {
        await tx.query(`UPDATE territories SET status = 'INACTIVE', v5_retired_game_day = $2 WHERE id = $1 AND status = 'ACTIVE'`, [container.id, day]);
        retired += 1;
      }
    }
  }
  return { ok: true, day, corporations: states.length, created, retired, billingBasis: 'occupied_capacity_not_container_count' };
}
