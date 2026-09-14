import type { PostgresRepository } from './repository.ts';

/** Rebuilds the authoritative Territory capacity/service projection at day close. */
export async function settleTerritoryCapacityProjections(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const territories = await repository.query<{ id: string }>("SELECT id FROM territories WHERE status = 'ACTIVE' ORDER BY id");
  for (const territory of territories.rows) {
    await repository.query('SELECT earth_refresh_territory_capacity($1, $2)', [territory.id, gameDay]);
  }
  return { ok: true, gameDay, territoriesRefreshed: territories.rows.length, projection: 'territory_capacity_state' };
}

/** Corporation-local settlement hook; Territory remains the geographic projection boundary. */
export async function settleCorporationDynamics(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const corporations = await repository.query("SELECT id FROM corporations WHERE status = 'ACTIVE' ORDER BY id");
  return { ok: true, gameDay, corporationsSettled: corporations.rows.length, localAuthority: 'CORPORATION' };
}
