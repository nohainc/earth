import type { PostgresRepository } from './repository.ts';

/** Rebuilds the authoritative Territory capacity/service projection at day close. */
// @mutation-boundary deterministic-settlement: capacity projections are recomputed from canonical facts for a day.
// @mutation-boundary caller-owned-transaction: projection refresh is a settlement phase transaction.
export async function settleTerritoryCapacityProjections(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const territories = await repository.query<{ id: string }>("SELECT id FROM territories WHERE status = 'ACTIVE' ORDER BY id");
  for (const territory of territories.rows) {
    await repository.query('SELECT earth_refresh_territory_capacity($1, $2)', [territory.id, gameDay]);
  }
  return { ok: true, gameDay, territoriesRefreshed: territories.rows.length, projection: 'territory_capacity_state' };
}

/** Corporation-local operating projection; Territory remains the geographic projection boundary. */
// @mutation-boundary deterministic-settlement: the corporation snapshot is recomputed from canonical facts for a day.
// @mutation-boundary caller-owned-transaction: corporation dynamics run within the settlement phase transaction.
export async function settleCorporationDynamics(repository: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const corporations = await repository.query<{ id: string }>("SELECT id FROM corporations WHERE status = 'ACTIVE' ORDER BY id");
  let snapshotsWritten = 0;
  for (const corporation of corporations.rows) {
    const facts = (await repository.query<{
      active_territory_count: string;
      active_house_count: string;
      active_building_count: string;
      service_capacity_units: string;
      service_allocated_units: string;
      operating_cost_units: string;
      service_revenue_units: string;
      active_research_project_count: string;
      organization_financial_status: string | null;
    }>(`WITH corporation_economies AS (
      SELECT economic_id FROM owner_registry WHERE owner_type = 'CORPORATION' AND economic_id = $1
      UNION
      SELECT oe.economic_id
        FROM organization_legacy_map lm
        JOIN organization_economies oe ON oe.organization_id = lm.organization_id
       WHERE lm.legacy_type = 'CORPORATION' AND lm.legacy_id = $2
    ), corporation_buildings AS (
      SELECT b.id, b.owner_economic_id, b.catalog_id
        FROM buildings b
        JOIN corporation_economies ce ON ce.economic_id = b.owner_economic_id
       WHERE b.status = 'ACTIVE'
    )
    SELECT
      (SELECT COUNT(*) FROM territories WHERE corporation_id = $2 AND status = 'ACTIVE')::TEXT AS active_territory_count,
      (SELECT COUNT(DISTINCT house_id) FROM house_affiliations WHERE corporation_id = $2 AND status = 'ACTIVE')::TEXT AS active_house_count,
      (SELECT COUNT(*) FROM corporation_buildings)::TEXT AS active_building_count,
      (SELECT COALESCE(SUM(c.service_capacity_units), 0) FROM corporation_buildings b JOIN building_catalog c ON c.id = b.catalog_id WHERE c.economic_role = 'SERVICE')::TEXT AS service_capacity_units,
      (SELECT COALESCE(SUM(sa.allocated_units), 0) FROM service_allocations sa JOIN corporation_economies ce ON ce.economic_id = sa.provider_economic_id WHERE sa.game_day = $3)::TEXT AS service_allocated_units,
      (SELECT COALESCE(SUM(c.operating_credit_units), 0) FROM corporation_buildings b JOIN building_catalog c ON c.id = b.catalog_id)::TEXT AS operating_cost_units,
      (SELECT COALESCE(SUM(sa.price_units), 0) FROM service_allocations sa JOIN corporation_economies ce ON ce.economic_id = sa.provider_economic_id WHERE sa.game_day = $3)::TEXT AS service_revenue_units,
      (SELECT COUNT(*) FROM corporation_research_projects p JOIN corporation_economies ce ON ce.economic_id = p.corporation_economic_id WHERE p.status IN ('QUEUED', 'ACTIVE'))::TEXT AS active_research_project_count,
      (SELECT fs.status FROM organization_legacy_map lm JOIN organization_financial_states fs ON fs.organization_id = lm.organization_id WHERE lm.legacy_type = 'CORPORATION' AND lm.legacy_id = $2) AS organization_financial_status`, [corporation.id, corporation.id, gameDay])).rows[0];
    await repository.query(`INSERT INTO corporation_operating_snapshots (corporation_id, game_day, active_territory_count, active_house_count, active_building_count, service_capacity_units, service_allocated_units, operating_cost_units, service_revenue_units, active_research_project_count, organization_financial_status, rules_version)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'corporation-operating-v1')
      ON CONFLICT (corporation_id, game_day) DO UPDATE SET active_territory_count = EXCLUDED.active_territory_count, active_house_count = EXCLUDED.active_house_count, active_building_count = EXCLUDED.active_building_count, service_capacity_units = EXCLUDED.service_capacity_units, service_allocated_units = EXCLUDED.service_allocated_units, operating_cost_units = EXCLUDED.operating_cost_units, service_revenue_units = EXCLUDED.service_revenue_units, active_research_project_count = EXCLUDED.active_research_project_count, organization_financial_status = EXCLUDED.organization_financial_status, rules_version = EXCLUDED.rules_version, updated_at = CURRENT_TIMESTAMP`, [corporation.id, gameDay, Number(facts?.active_territory_count ?? 0), Number(facts?.active_house_count ?? 0), Number(facts?.active_building_count ?? 0), facts?.service_capacity_units ?? '0', facts?.service_allocated_units ?? '0', facts?.operating_cost_units ?? '0', facts?.service_revenue_units ?? '0', Number(facts?.active_research_project_count ?? 0), facts?.organization_financial_status ?? null]);
    snapshotsWritten += 1;
  }
  return { ok: true, gameDay, corporationsSettled: corporations.rows.length, snapshotsWritten, projection: 'corporation_operating_snapshots', localAuthority: 'CORPORATION' };
}
