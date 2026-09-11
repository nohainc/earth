import type { PostgresRepository } from '../repository.ts';

export interface ResourceFlowRate {
  grossProductionPerSecond: number;
  grossConsumptionPerSecond: number;
  netPerSecond: number;
  netPerGameDay: number;
}

export type ResourceFlowMap = Record<string, ResourceFlowRate>;

export const COMMODITIES = ['material', 'components', 'energy', 'compute', 'food', 'credits'] as const;

export async function computeResourceFlows(
  repo: PostgresRepository,
  humanId: string,
): Promise<ResourceFlowMap> {
  const flows: ResourceFlowMap = {};

  for (const c of COMMODITIES) {
    flows[c] = {
      grossProductionPerSecond: 0,
      grossConsumptionPerSecond: 0,
      netPerSecond: 0,
      netPerGameDay: 0,
    };
  }

  // Active private buildings use the DB-catalog-backed V2 calculator. This
  // keeps previews and live flow projections on the same policy rules as
  // settlement posting.
  const buildings = await repo.query<{
    asset_code: string;
    output_units: string | number | null;
    upkeep_units: string | number | null;
    operating_units: string | number | null;
    effective_output_multiplier: string | number | null;
    effective_cost_multiplier: string | number | null;
  }>(`
    SELECT economics.asset_code, economics.output_units, economics.upkeep_units,
           economics.operating_units, economics.effective_output_multiplier,
           economics.effective_cost_multiplier
    FROM buildings b
    CROSS JOIN LATERAL earth_calculate_building_economics(b.id) economics
    WHERE b.owner_id = $1 AND b.ownership_class = 'private' AND b.status = 'active'
  `, [humanId]).catch(() => ({ rows: [] }));

  for (const b of buildings.rows) {
    const commodity = b.asset_code.toLowerCase() === 'credit' ? 'credits' : b.asset_code.toLowerCase();
    if (!(commodity in flows)) continue;
    flows[commodity].grossProductionPerSecond += (Number(b.output_units ?? 0) * Number(b.effective_output_multiplier ?? 1)) / 1440;
    flows[commodity].grossConsumptionPerSecond += ((Number(b.upkeep_units ?? 0) + Number(b.operating_units ?? 0)) * Number(b.effective_cost_multiplier ?? 1)) / 1440;
  }

  // Research project funding flows (credits consumption)
  const research = await repo.query<{ credit_cost_units: string }>(
    `SELECT p.credit_cost_units::TEXT FROM corporation_research_projects p
     JOIN memberships m ON m.corporation_id = (SELECT source_id FROM owner_registry WHERE economic_id = p.corporation_economic_id)
     WHERE m.human_id = $1 AND p.target_type = 'TECHNOLOGY' AND p.status = 'ACTIVE'`, [humanId],
  ).catch(() => ({ rows: [] }));
  for (const r of research.rows) {
    const dailyBudget = Number(r.credit_cost_units ?? 0) / 100;
    flows.credits.grossConsumptionPerSecond += dailyBudget / 1440;
  }

  // Compute final net per second and net per game day
  for (const c of COMMODITIES) {
    const grossProd = Math.round(flows[c].grossProductionPerSecond * 10000) / 10000;
    const grossCons = Math.round(flows[c].grossConsumptionPerSecond * 10000) / 10000;
    const netPerSec = Math.round((grossProd - grossCons) * 10000) / 10000;
    const netPerDay = Math.round(netPerSec * 1440 * 100) / 100;

    flows[c] = {
      grossProductionPerSecond: grossProd,
      grossConsumptionPerSecond: grossCons,
      netPerSecond: netPerSec,
      netPerGameDay: netPerDay,
    };
  }

  return flows;
}
