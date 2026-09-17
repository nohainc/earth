import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { toJsonSafe } from './json-safe.ts';

async function activeHouse(tx: PostgresRepository, humanId: string) {
  const row = (await tx.query<{ house_id: string; corporation_id: string | null }>(`SELECT h.house_id, ha.corporation_id
    FROM humans h LEFT JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
    WHERE h.id = $1 AND h.status = 'ACTIVE' FOR UPDATE`, [humanId])).rows[0];
  if (!row) throw new Error('Active House is required');
  return row;
}

export async function openV5CapacityResolutionCase(repository: PostgresRepository, input: { humanId: string; reason?: string }) {
  return repository.transaction(async (tx) => {
    const house = await activeHouse(tx, input.humanId);
    const delinquency = (await tx.query<{ status: string; consecutive_missed_days: number }>(`SELECT status, consecutive_missed_days FROM v5_capacity_delinquency_state WHERE subject_type = 'HOUSE' AND subject_id = $1`, [house.house_id])).rows[0];
    if (!delinquency || !['PRODUCTIVE_CAPACITY_SUSPENDED', 'EXPANSION_BLOCKED'].includes(delinquency.status)) throw new Error('A House capacity delinquency is required before opening a resolution case');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const id = `V5-RES-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO v5_capacity_resolution_cases (id, house_id, corporation_id, trigger_status, opened_game_day, opened_by_human_id, resolution_reason) VALUES ($1,$2,$3,$4,$5,$6,$7)`, [id, house.house_id, house.corporation_id, delinquency.status, day, input.humanId, input.reason ?? null]);
    await tx.query(`UPDATE buildings b SET v5_productive_status = 'SUSPENDED' FROM owner_registry o WHERE o.id = $1 AND o.owner_type = 'HOUSE' AND b.owner_economic_id = o.economic_id AND b.status = 'ACTIVE'`, [house.house_id]);
    await createGameEvent(tx, { id: `V5-RES-OPEN-${id}`, category: 'FINANCE', eventType: 'V5_CAPACITY_RESOLUTION_OPENED', gameDay: day, actorHumanId: input.humanId, subjectType: 'HOUSE', subjectId: house.house_id, title: 'House capacity resolution case opened', details: { caseId: id, triggerStatus: delinquency.status, reason: input.reason ?? null }, correlationId: `v5-resolution:${id}` });
    return { ok: true, caseId: id, houseId: house.house_id, corporationId: house.corporation_id, status: 'OPEN', triggerStatus: delinquency.status, gameDay: day };
  });
}

export async function listV5CapacityResolutionCases(repository: PostgresRepository, humanId: string) {
  return repository.transaction(async (tx) => {
    const house = await activeHouse(tx, humanId);
    const cases = await tx.query(`SELECT c.*, COALESCE(jsonb_agg(jsonb_build_object('buildingId', a.building_id, 'footprintUnits', a.footprint_units, 'proceedsUnits', a.proceeds_units, 'resolvedGameDay', a.resolved_game_day) ORDER BY a.building_id) FILTER (WHERE a.building_id IS NOT NULL), '[]'::JSONB) AS assets
      FROM v5_capacity_resolution_cases c LEFT JOIN v5_capacity_resolution_assets a ON a.case_id = c.id WHERE c.house_id = $1 GROUP BY c.id ORDER BY c.opened_game_day DESC, c.id DESC`, [house.house_id]);
    return { ok: true, houseId: house.house_id, cases: toJsonSafe(cases.rows) };
  });
}

export async function liquidateV5HouseBuilding(repository: PostgresRepository, input: { humanId: string; caseId: string; buildingId: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    const house = await activeHouse(tx, input.humanId);
    const resolution = (await tx.query<{ id: string; status: string }>('SELECT id, status FROM v5_capacity_resolution_cases WHERE id = $1 AND house_id = $2 FOR UPDATE', [input.caseId, house.house_id])).rows[0];
    if (!resolution || !['OPEN', 'MOTHBALLED'].includes(resolution.status)) throw new Error('Open House capacity resolution case not found');
    const building = (await tx.query<{ id: string; footprint: string; status: string }>(`SELECT b.id, bc.slot_footprint::TEXT AS footprint, b.status FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id JOIN owner_registry o ON o.economic_id = b.owner_economic_id AND o.id = $1 AND o.owner_type = 'HOUSE' WHERE b.id = $2 AND b.status IN ('ACTIVE','UNDER_CONSTRUCTION') FOR UPDATE`, [house.house_id, input.buildingId])).rows[0];
    if (!building) throw new Error('Active House building not found');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    await tx.query("UPDATE buildings SET status = 'INACTIVE', v5_productive_status = 'ACTIVE' WHERE id = $1", [building.id]);
    await refreshV5SettlementProfilesForHouse(tx, house.house_id, day);
    await tx.query(`INSERT INTO v5_capacity_resolution_assets (case_id, building_id, footprint_units, resolved_game_day) VALUES ($1,$2,$3,$4)`, [input.caseId, building.id, building.footprint, day]);
    await createGameEvent(tx, { id: `V5-RES-LIQ-${input.correlationId}`, category: 'FINANCE', eventType: 'V5_CAPACITY_ASSET_RELEASED', gameDay: day, actorHumanId: input.humanId, subjectType: 'BUILDING', subjectId: building.id, title: 'Productive building capacity released', details: { caseId: input.caseId, footprintUnits: building.footprint, proceedsUnits: '0' }, correlationId: input.correlationId });
    return { ok: true, caseId: input.caseId, buildingId: building.id, status: 'INACTIVE', releasedFootprintUnits: building.footprint, proceedsUnits: '0', gameDay: day, correlationId: input.correlationId };
  });
}
