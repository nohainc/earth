import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';

async function activeHouse(tx: PostgresRepository, humanId: string): Promise<{ houseId: string; currentTerritoryId: string | null }> {
  const row = (await tx.query<{ houseId: string; currentTerritoryId: string | null }>(`SELECT h.house_id AS "houseId", r.territory_id AS "currentTerritoryId" FROM humans h LEFT JOIN house_residencies r ON r.house_id = h.house_id AND r.status = 'ACTIVE' AND r.residency_class = 'PRIMARY' WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId])).rows[0];
  if (!row) throw new Error('Active Human not found');
  return row;
}

async function worldDay(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

export async function getHouseResidency(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const house = await activeHouse(repository, humanId);
  const result = await repository.query(`SELECT r.*, t.name AS territory_name, t.status AS territory_status, COALESCE(g.governing_institution_id, t.corporation_id) AS governing_institution_id FROM house_residencies r JOIN territories t ON t.id = r.territory_id LEFT JOIN territory_governance g ON g.territory_id = t.id AND g.status = 'ACTIVE' WHERE r.house_id = $1 ORDER BY r.status, r.residency_class, r.effective_from_game_day DESC`, [house.houseId]);
  return { houseId: house.houseId, primaryTerritoryId: house.currentTerritoryId, residencies: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function quoteHouseMove(repository: PostgresRepository, humanId: string, territoryId: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const house = await activeHouse(tx, humanId);
    const territory = (await tx.query(`SELECT t.id, t.name, t.status, s.house_capacity, s.active_house_count, COALESCE(g.governing_institution_id, t.corporation_id) AS governing_institution_id FROM territories t LEFT JOIN territory_capacity_state s ON s.territory_id = t.id LEFT JOIN territory_governance g ON g.territory_id = t.id AND g.status = 'ACTIVE' WHERE t.id = $1`, [territoryId])).rows[0];
    if (!territory || territory.status !== 'ACTIVE') throw new Error('Target Territory is unavailable');
    const available = BigInt(String(territory.house_capacity ?? 0)) - BigInt(String(territory.active_house_count ?? 0));
    const economicOwner = (await tx.query<{ economic_id: string }>('SELECT economic_id FROM owner_registry WHERE id = $1 AND owner_type = \'HOUSE\'', [house.houseId])).rows[0];
    const remoteAssets = await tx.query<{ territory_id: string; count: string }>("SELECT territory_id, COUNT(*)::TEXT AS count FROM buildings WHERE owner_economic_id = $1 AND status = 'ACTIVE' AND territory_id <> $2 GROUP BY territory_id ORDER BY territory_id", [economicOwner?.economic_id, territoryId]);
    const obligations = await tx.query<{ nexus_type: string; amount: string; due_game_day: number }>("SELECT COALESCE(nexus_type, 'RESIDENCE') AS nexus_type, SUM(principal_due_units + interest_due_units - paid_units)::TEXT AS amount, MIN(due_game_day) AS due_game_day FROM financial_obligations WHERE debtor_economic_id = $1 AND status IN ('DUE','PARTIAL','ARREARS') GROUP BY nexus_type ORDER BY nexus_type", [economicOwner?.economic_id]);
    return { currentTerritoryId: house.currentTerritoryId, targetTerritory: territory, eligible: available > 0n || house.currentTerritoryId === territoryId, moveCostUnits: '0', effectiveBoundary: 'next_settlement_day', remoteAssets: remoteAssets.rows, obligationsByNexus: obligations.rows, assetLocationRetained: true };
  });
}

export async function moveHouseResidence(repository: PostgresRepository, input: { humanId: string; territoryId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const house = await activeHouse(tx, input.humanId);
    const ids = [input.territoryId, ...(house.currentTerritoryId ? [house.currentTerritoryId] : [])];
    const locked = await tx.query<{ id: string; name: string; status: string; house_capacity: string; active_house_count: string }>('SELECT t.id, t.name, t.status, s.house_capacity::TEXT, s.active_house_count::TEXT FROM territories t JOIN territory_capacity_state s ON s.territory_id = t.id WHERE t.id = ANY($1::TEXT[]) ORDER BY t.id FOR UPDATE', [ids]);
    const target = locked.rows.find((row) => row.id === input.territoryId);
    if (!target || target.status !== 'ACTIVE') throw new Error('Target Territory is unavailable');
    if (house.currentTerritoryId === input.territoryId) return { ok: true, alreadyProcessed: true, territoryId: input.territoryId, correlationId: input.correlationId };
    if (BigInt(target.active_house_count) >= BigInt(target.house_capacity)) throw new Error('Target Territory residence capacity exceeded');
    const day = await worldDay(tx);
    await tx.query(`UPDATE house_residencies SET status = 'ENDED', effective_to_game_day = $1 WHERE house_id = $2 AND status = 'ACTIVE' AND residency_class = 'PRIMARY'`, [day, house.houseId]);
    await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, effective_from_game_day, correlation_id) VALUES ($1,$2,$3,'PRIMARY',$4,$5)`, [`RES-${crypto.randomUUID()}`, house.houseId, input.territoryId, day + 1, input.correlationId]);
    await tx.query(`UPDATE territory_capacity_state SET active_house_count = active_house_count + 1 WHERE territory_id = $1`, [input.territoryId]);
    if (house.currentTerritoryId) await tx.query(`UPDATE territory_capacity_state SET active_house_count = GREATEST(0, active_house_count - 1) WHERE territory_id = $1`, [house.currentTerritoryId]);
    await createGameEvent(tx, { id: `RESIDENCY-MOVED-${input.correlationId}`, category: 'HOUSE', eventType: 'HOUSE_RESIDENCY_CHANGED', gameDay: day, actorHumanId: input.humanId, subjectType: 'HOUSE', subjectId: house.houseId, title: `Residence moved to ${target.name}`, details: { fromTerritoryId: house.currentTerritoryId, toTerritoryId: input.territoryId, effectiveGameDay: day + 1 }, correlationId: input.correlationId });
    return { ok: true, territoryId: input.territoryId, effectiveGameDay: day + 1, remoteAssetsRetained: true, correlationId: input.correlationId };
  });
}
