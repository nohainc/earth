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

  // Research project funding flows (credits consumption)
  const research = await repo.query<{ budget: string }>(
    "SELECT budget FROM research_projects WHERE owner_id = $1 AND status = 'active'",
    [humanId],
  );
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
