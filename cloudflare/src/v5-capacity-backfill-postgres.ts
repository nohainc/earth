import type { PostgresRepository } from './repository.ts';

// @mutation-boundary deterministic-settlement
// runId + sourceGameDay provide the resumable idempotency boundary.

type BackfillPolicy = {
  standardCapacity: bigint;
  version: number;
};

async function policyForDay(repository: PostgresRepository, gameDay: number): Promise<BackfillPolicy> {
  const row = (await repository.query<{ standard_territory_capacity_units: string; version: number }>(
    `SELECT standard_territory_capacity_units::TEXT, version
       FROM v5_capacity_policy_versions
      WHERE status = 'ACTIVE' AND effective_from_game_day <= $1
        AND (effective_to_game_day IS NULL OR effective_to_game_day >= $1)
      ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`,
    [gameDay],
  )).rows[0];
  if (!row) throw new Error('No active V5 capacity policy exists for the backfill day');
  return { standardCapacity: BigInt(row.standard_territory_capacity_units), version: Number(row.version) };
}

function requiredUnits(occupied: bigint, standardCapacity: bigint): bigint {
  return occupied === 0n ? 0n : (occupied + standardCapacity - 1n) / standardCapacity;
}

/**
 * Backfill one bounded batch of canonical V5 capacity facts. It is safe to
 * rerun: the run cursor and day-keyed projections make each batch idempotent.
 */
export async function backfillV5CapacityBatch(
  repository: PostgresRepository,
  input: { runId: string; sourceGameDay: number; batchSize?: number },
): Promise<Record<string, unknown>> {
  const batchSize = Math.max(1, Math.min(250, Math.trunc(input.batchSize ?? 50)));
  if (!input.runId.trim() || !Number.isInteger(input.sourceGameDay) || input.sourceGameDay < 1) {
    throw new Error('A valid V5 backfill run ID and source game day are required');
  }
  return repository.transaction(async (tx) => {
    const policy = await policyForDay(tx, input.sourceGameDay);
    await tx.query(
      `INSERT INTO v5_capacity_backfill_runs (id, source_game_day)
       VALUES ($1, $2) ON CONFLICT (source_game_day) DO NOTHING`,
      [input.runId, input.sourceGameDay],
    );
    const run = (await tx.query<{
      id: string;
      cursor_corporation_id: string | null;
      status: string;
    }>(
      'SELECT id, cursor_corporation_id, status FROM v5_capacity_backfill_runs WHERE source_game_day = $1 FOR UPDATE',
      [input.sourceGameDay],
    )).rows[0];
    if (!run) throw new Error('V5 backfill run could not be created');
    if (run.id !== input.runId) throw new Error('A different backfill run already owns this source day');
    if (run.status === 'COMPLETED') return { ok: true, alreadyCompleted: true, runId: run.id, sourceGameDay: input.sourceGameDay };

    const corporations = (await tx.query<{ id: string }>(
      `SELECT id FROM corporations
        WHERE ($1::TEXT IS NULL OR id > $1)
        ORDER BY id LIMIT $2`,
      [run.cursor_corporation_id, batchSize],
    )).rows;
    let housesProcessed = 0;
    let buildingUnitsProcessed = 0n;
    for (const corporation of corporations) {
      const houses = (await tx.query<{ house_id: string; building_units: string }>(
        `SELECT ha.house_id,
                COALESCE((SELECT SUM(bc.slot_footprint)
                            FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
                           WHERE b.owner_economic_id = ho.economic_id AND b.status = 'ACTIVE'), 0)::TEXT AS building_units
           FROM house_affiliations ha
           JOIN owner_registry ho ON ho.id = ha.house_id AND ho.owner_type = 'HOUSE'
          WHERE ha.corporation_id = $1 AND ha.status = 'ACTIVE'
          ORDER BY ha.house_id`,
        [corporation.id],
      )).rows;
      const publicBuildings = (await tx.query<{ units: string }>(
        `SELECT COALESCE(SUM(bc.slot_footprint), 0)::TEXT AS units
           FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
           JOIN owner_registry owner ON owner.economic_id = b.owner_economic_id
            AND owner.id = $1 AND owner.owner_type = 'CORPORATION'
          WHERE b.status = 'ACTIVE' AND bc.ownership_scope = 'PUBLIC'`,
        [corporation.id],
      )).rows[0];
      const privateUnits = houses.reduce((total, house) => total + BigInt(house.building_units), 0n);
      const publicUnits = BigInt(publicBuildings?.units ?? 0);
      const residentialUnits = BigInt(houses.length);
      const occupied = residentialUnits + privateUnits + publicUnits;
      await tx.query(
        `INSERT INTO corporation_capacity_state_v5
          (corporation_id, game_day, residential_units_used, private_building_units_used,
           public_building_units_used, total_occupied_units, standard_territory_capacity_units,
           required_territory_units, rules_version)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (corporation_id, game_day) DO UPDATE SET
           residential_units_used = EXCLUDED.residential_units_used,
           private_building_units_used = EXCLUDED.private_building_units_used,
           public_building_units_used = EXCLUDED.public_building_units_used,
           total_occupied_units = EXCLUDED.total_occupied_units,
           standard_territory_capacity_units = EXCLUDED.standard_territory_capacity_units,
           required_territory_units = EXCLUDED.required_territory_units,
           rules_version = EXCLUDED.rules_version,
           updated_at = CURRENT_TIMESTAMP`,
        [corporation.id, input.sourceGameDay, residentialUnits.toString(), privateUnits.toString(), publicUnits.toString(), occupied.toString(), policy.standardCapacity.toString(), requiredUnits(occupied, policy.standardCapacity).toString(), `v5-capacity-policy:${policy.version}`],
      );
      for (const house of houses) {
        const buildingUnits = BigInt(house.building_units);
        const base = (await tx.query<{ rate: string }>(
          `SELECT house_base_capacity_rate_units::TEXT AS rate
             FROM corporation_capacity_policy_versions
            WHERE corporation_id = $1 AND status = 'ACTIVE'
              AND effective_from_game_day <= $2
              AND (effective_to_game_day IS NULL OR effective_to_game_day >= $2)
            ORDER BY effective_from_game_day DESC, version DESC LIMIT 1`,
          [corporation.id, input.sourceGameDay],
        )).rows[0]?.rate ?? '0';
        await tx.query(
          `INSERT INTO house_capacity_statements_v5
            (house_id, corporation_id, game_day, residential_units, building_units, total_units,
             base_rate_units, progressive_schedule_id, assessed_rent_units, paid_rent_units,
             arrears_units, delinquency_status, rules_version)
           VALUES ($1,$2,$3,1,$4,$5,$6,NULL,0,0,0,'CURRENT',$7)
           ON CONFLICT (house_id, game_day) DO UPDATE SET
             corporation_id = EXCLUDED.corporation_id, building_units = EXCLUDED.building_units,
             total_units = EXCLUDED.total_units, base_rate_units = EXCLUDED.base_rate_units,
             rules_version = EXCLUDED.rules_version`,
          [house.house_id, corporation.id, input.sourceGameDay, buildingUnits.toString(), (1n + buildingUnits).toString(), base, `v5-capacity-policy:${policy.version}`],
        );
      }
      housesProcessed += houses.length;
      buildingUnitsProcessed += privateUnits + publicUnits;
    }
    const nextCursor = corporations.at(-1)?.id ?? run.cursor_corporation_id;
    const completed = corporations.length < batchSize;
    await tx.query(
      `UPDATE v5_capacity_backfill_runs
          SET cursor_corporation_id = $2,
              status = CASE WHEN $3 THEN 'COMPLETED' ELSE 'RUNNING' END,
              corporations_processed = corporations_processed + $4,
              houses_processed = houses_processed + $5,
              building_units_processed = building_units_processed + $6,
              completed_at = CASE WHEN $3 THEN CURRENT_TIMESTAMP ELSE completed_at END
        WHERE id = $1`,
      [run.id, nextCursor, completed, corporations.length, housesProcessed, buildingUnitsProcessed.toString()],
    );
    return { ok: true, runId: run.id, sourceGameDay: input.sourceGameDay, corporationsProcessed: corporations.length, housesProcessed, buildingUnitsProcessed: buildingUnitsProcessed.toString(), completed };
  });
}

export async function getV5CapacityBackfillRun(repository: PostgresRepository, sourceGameDay: number): Promise<Record<string, unknown>> {
  const result = await repository.query('SELECT * FROM v5_capacity_backfill_runs WHERE source_game_day = $1', [sourceGameDay]);
  return { ok: true, run: result.rows[0] ?? null, generatedFrom: 'postgres-canonical-facts-v5' };
}
