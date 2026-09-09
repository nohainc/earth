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

  // Active private buildings output and upkeep flows
  const buildings = await repo.query<{
    output_credits: string | number | null;
    output_energy: string | number | null;
    output_food: string | number | null;
    output_materials: string | number | null;
    output_components: string | number | null;
    output_compute: string | number | null;
    upkeep_credits: string | number | null;
    upkeep_energy: string | number | null;
    upkeep_food: string | number | null;
    upkeep_materials: string | number | null;
    upkeep_components: string | number | null;
    upkeep_compute: string | number | null;
    operating_credits: string | number | null;
    operating_energy: string | number | null;
    operating_food: string | number | null;
    operating_materials: string | number | null;
    operating_components: string | number | null;
    operating_compute: string | number | null;
    operating_policy: string | null;
    resource_output_type: string | null;
    resource_output_amount: string | number | null;
  }>(`
    SELECT
      COALESCE(bc.output_credits, CASE WHEN b.resource_output_type = 'credits' OR b.resource_output_type IS NULL THEN b.resource_output_amount ELSE 0 END, 0) AS output_credits,
      COALESCE(bc.output_energy, CASE WHEN b.resource_output_type = 'energy' THEN b.resource_output_amount ELSE 0 END, 0) AS output_energy,
      COALESCE(bc.output_food, CASE WHEN b.resource_output_type = 'food' THEN b.resource_output_amount ELSE 0 END, 0) AS output_food,
      COALESCE(bc.output_materials, CASE WHEN b.resource_output_type IN ('material', 'materials') THEN b.resource_output_amount ELSE 0 END, 0) AS output_materials,
      COALESCE(bc.output_components, CASE WHEN b.resource_output_type = 'components' THEN b.resource_output_amount ELSE 0 END, 0) AS output_components,
      COALESCE(bc.output_compute, CASE WHEN b.resource_output_type = 'compute' THEN b.resource_output_amount ELSE 0 END, 0) AS output_compute,
      COALESCE(bc.upkeep_credits, 0) AS upkeep_credits,
      COALESCE(bc.upkeep_energy, b.upkeep_energy, 0) AS upkeep_energy,
      COALESCE(bc.upkeep_food, b.upkeep_food, 0) AS upkeep_food,
      COALESCE(bc.upkeep_materials, b.upkeep_materials, 0) AS upkeep_materials,
      COALESCE(bc.upkeep_components, b.upkeep_components, 0) AS upkeep_components,
      COALESCE(bc.upkeep_compute, b.upkeep_compute, 0) AS upkeep_compute,
      COALESCE(bc.operating_credits, b.daily_operating_credits, 0) AS operating_credits,
      COALESCE(bc.operating_energy, 0) AS operating_energy,
      COALESCE(bc.operating_food, 0) AS operating_food,
      COALESCE(bc.operating_materials, 0) AS operating_materials,
      COALESCE(bc.operating_components, 0) AS operating_components,
      COALESCE(bc.operating_compute, 0) AS operating_compute,
      b.operating_policy,
      b.resource_output_type,
      b.resource_output_amount
    FROM buildings b
    LEFT JOIN building_catalog bc ON bc.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE b.owner_id = $1 AND b.ownership_class = 'private' AND b.status = 'active'
  `, [humanId]).catch(() => ({ rows: [] }));

  for (const b of buildings.rows) {
    let outMult = 1.0;
    let costMult = 1.0;
    const policy = (b.operating_policy || 'balanced').toLowerCase();

    if (policy === 'high_output') {
      outMult = 1.3;
      costMult = 1.4;
    } else if (policy === 'frugal' || policy === 'eco_reserve') {
      outMult = 0.75;
      costMult = 0.7;
    } else if (policy === 'halted') {
      outMult = 0.0;
      costMult = 0.2;
    }

    // Commodity production (per second = daily / 1440)
    flows.credits.grossProductionPerSecond += (Number(b.output_credits ?? 0) * outMult) / 1440;
    flows.energy.grossProductionPerSecond += (Number(b.output_energy ?? 0) * outMult) / 1440;
    flows.food.grossProductionPerSecond += (Number(b.output_food ?? 0) * outMult) / 1440;
    flows.material.grossProductionPerSecond += (Number(b.output_materials ?? 0) * outMult) / 1440;
    flows.components.grossProductionPerSecond += (Number(b.output_components ?? 0) * outMult) / 1440;
    flows.compute.grossProductionPerSecond += (Number(b.output_compute ?? 0) * outMult) / 1440;

    // Commodity consumption (upkeep + operating per second)
    flows.credits.grossConsumptionPerSecond += ((Number(b.upkeep_credits ?? 0) + Number(b.operating_credits ?? 0)) * costMult) / 1440;
    flows.energy.grossConsumptionPerSecond += ((Number(b.upkeep_energy ?? 0) + Number(b.operating_energy ?? 0)) * costMult) / 1440;
    flows.food.grossConsumptionPerSecond += ((Number(b.upkeep_food ?? 0) + Number(b.operating_food ?? 0)) * costMult) / 1440;
    flows.material.grossConsumptionPerSecond += ((Number(b.upkeep_materials ?? 0) + Number(b.operating_materials ?? 0)) * costMult) / 1440;
    flows.components.grossConsumptionPerSecond += ((Number(b.upkeep_components ?? 0) + Number(b.operating_components ?? 0)) * costMult) / 1440;
    flows.compute.grossConsumptionPerSecond += ((Number(b.upkeep_compute ?? 0) + Number(b.operating_compute ?? 0)) * costMult) / 1440;
  }

  // Research project funding flows (credits consumption)
  const research = await repo.query<{ budget: string }>(
    "SELECT budget FROM research_projects WHERE owner_id = $1 AND status = 'active'",
    [humanId],
  ).catch(() => ({ rows: [] }));
  for (const r of research.rows) {
    const dailyBudget = Number(r.budget ?? 0);
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
