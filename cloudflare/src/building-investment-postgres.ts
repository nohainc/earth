import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';

export async function upgradeBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const building = (await tx.query<{ id: string; owner_economic_id: string; territory_id: string; territory_right_id: string | null; family_code: string; tier: number; catalog_id: string; construction_credit_units: string; construction_minutes: number }>(`SELECT b.id, b.owner_economic_id, b.territory_id, b.territory_right_id, c.family_code, c.tier, c.id AS catalog_id, c.construction_credit_units::TEXT, c.construction_minutes FROM buildings b JOIN building_catalog c ON c.id = b.catalog_id JOIN humans h ON h.id = $2 AND h.house_id = (SELECT id FROM owner_registry WHERE economic_id = b.owner_economic_id AND owner_type = 'HOUSE') AND h.status = 'ACTIVE' WHERE b.id = $1 AND b.status = 'ACTIVE' FOR UPDATE`, [input.buildingId, input.humanId])).rows[0];
    if (!building) throw new Error('Building not found or not owned by the active House');
    if (building.tier >= 5) throw new Error('Building is already at the maximum tier');
    if ((await tx.query("SELECT 1 FROM construction_projects WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId])).rows[0]) throw new Error('This building already has an investment project in progress');
    const next = (await tx.query<{ id: string; construction_credit_units: string; construction_minutes: number }>('SELECT id, construction_credit_units::TEXT, construction_minutes FROM building_catalog WHERE family_code = $1 AND tier = $2', [building.family_code, building.tier + 1])).rows[0];
    if (!next) throw new Error('Next building tier is unavailable');
    const cost = BigInt(next.construction_credit_units) - BigInt(building.construction_credit_units);
    const wallet = (await tx.query<{ id: string; balance_units: string }>("SELECT id::TEXT, balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET' AND status = 'ACTIVE' FOR UPDATE", [building.owner_economic_id])).rows[0];
    const sink = (await tx.query<{ id: string }>("SELECT a.id::TEXT FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.economic_id = 'ECON-CONSTRUCTION-SETTLEMENT' AND a.asset_id = 1 AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE' LIMIT 1")).rows[0];
    if (!wallet || !sink || BigInt(wallet.balance_units) < cost) throw new Error('Insufficient Credits for tier upgrade');
    await tx.query(`SELECT earth_post_transaction($1,$2,1439,'ASSET_TRANSFER','PRIVATE_TIER_UPGRADE',$3,'building-investment-v1',$4::JSONB)`, [input.correlationId, day, input.buildingId, JSON.stringify([{ account_id: wallet.id, asset_id: 1, delta_units: (-cost).toString() }, { account_id: sink.id, asset_id: 1, delta_units: cost.toString() }])]);
    const projectId = `PROJECT-UPGRADE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const completion = day + Math.max(1, Math.ceil(Number(next.construction_minutes) / 1440));
    await tx.query(`INSERT INTO construction_projects (id, building_id, owner_economic_id, territory_id, target_catalog_id, credit_cost_units, resource_cost_units, started_game_day, expected_completion_game_day, status, correlation_id, territory_right_id, project_kind) VALUES ($1,$2,$3,$4,$5,$6,'{}'::JSONB,$7,$8,'IN_PROGRESS',$9,$10,'TIER_UPGRADE')`, [projectId, building.id, building.owner_economic_id, building.territory_id, next.id, cost.toString(), day, completion, input.correlationId, building.territory_right_id]);
    await tx.query("UPDATE buildings SET status = 'UNDER_CONSTRUCTION' WHERE id = $1", [building.id]);
    await createGameEvent(tx, { id: `BUILDING-UPGRADE-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_TIER_UPGRADE_STARTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: `Tier ${building.tier + 1} upgrade started`, details: { projectId, fromTier: building.tier, toTier: building.tier + 1, costUnits: cost.toString(), completionGameDay: completion }, correlationId: input.correlationId });
    return { ok: true, status: 'UNDER_CONSTRUCTION', projectId, fromTier: building.tier, toTier: building.tier + 1, creditCostUnits: cost.toString(), expectedCompletionGameDay: completion, correlationId: input.correlationId };
  });
}

export async function setBuildingOperatingMode(repository: PostgresRepository, input: { buildingId: string; humanId: string; mode: string; correlationId: string }): Promise<Record<string, unknown>> {
  const mode = input.mode.toUpperCase();
  if (!['CONSERVATIVE', 'BALANCED', 'GROWTH'].includes(mode)) throw new Error('Invalid building operating mode');
  const result = await repository.query<{ id: string; operating_mode: string }>(`UPDATE buildings b SET operating_mode = $1 FROM owner_registry o JOIN humans h ON h.house_id = o.id WHERE b.id = $2 AND o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE' AND h.id = $3 AND h.status = 'ACTIVE' RETURNING b.id, b.operating_mode`, [mode, input.buildingId, input.humanId]);
  if (!result.rows[0]) throw new Error('Building not found or not owned by the active House');
  return { ok: true, building: result.rows[0], correlationId: input.correlationId };
}

export async function decommissionBuilding(repository: PostgresRepository, input: { buildingId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const result = await tx.query<{ id: string; territory_id: string }>(`UPDATE buildings b SET status = 'INACTIVE' FROM owner_registry o JOIN humans h ON h.house_id = o.id WHERE b.id = $1 AND o.economic_id = b.owner_economic_id AND o.owner_type = 'HOUSE' AND h.id = $2 AND h.status = 'ACTIVE' AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION') RETURNING b.id, b.territory_id`, [input.buildingId, input.humanId]);
    if (!result.rows[0]) throw new Error('Building not found, inactive, or not owned by the active House');
    await tx.query("UPDATE construction_projects SET status = 'CANCELLED', cancelled_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE building_id = $1 AND status = 'IN_PROGRESS'", [input.buildingId, day]);
    await tx.query('SELECT earth_refresh_territory_capacity($1, $2)', [result.rows[0].territory_id, day]);
    await createGameEvent(tx, { id: `BUILDING-DECOMMISSIONED-${input.correlationId}`, category: 'BUILDING', eventType: 'BUILDING_DECOMMISSIONED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: input.buildingId, title: 'Building decommissioned', details: { buildingId: input.buildingId }, correlationId: input.correlationId });
    return { ok: true, status: 'INACTIVE', buildingId: input.buildingId, correlationId: input.correlationId };
  });
}
