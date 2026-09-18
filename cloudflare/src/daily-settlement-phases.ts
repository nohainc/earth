import type { PostgresRepository } from './repository.ts';

export type DailySettlementShardMode = 'all' | 'owner-shards';

export type DailySettlementPhaseContext = {
  tx: PostgresRepository;
  day: number;
  shard?: number;
  shardCount?: number;
};

export type DailySettlementPhase = {
  id: string;
  order: number;
  shardMode: DailySettlementShardMode;
  status: 'required' | 'deferred';
  execute: (context: DailySettlementPhaseContext) => Promise<unknown>;
};

export type DailySettlementPhaseHandlers = {
  v5PolicyActivation: (context: DailySettlementPhaseContext) => Promise<unknown>;
  constitutionSnapshots: (context: DailySettlementPhaseContext) => Promise<unknown>;
  activateSuccessors: (context: DailySettlementPhaseContext) => Promise<unknown>;
  preparePartitions: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rebuildProfiles: (context: DailySettlementPhaseContext) => Promise<unknown>;
  profileSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifeMaintenance: (context: DailySettlementPhaseContext) => Promise<unknown>;
  basicLevy: (context: DailySettlementPhaseContext) => Promise<unknown>;
  ipLicenseBilling: (context: DailySettlementPhaseContext) => Promise<unknown>;
  buildingSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  constructionCompletion: (context: DailySettlementPhaseContext) => Promise<unknown>;
  territoryLeaseSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  commonsDividendSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  corporationIncomeTax: (context: DailySettlementPhaseContext) => Promise<unknown>;
  publicTaxAssessment: (context: DailySettlementPhaseContext) => Promise<unknown>;
  taxReconciliation: (context: DailySettlementPhaseContext) => Promise<unknown>;
  globalBank: (context: DailySettlementPhaseContext) => Promise<unknown>;
  bankHealth: (context: DailySettlementPhaseContext) => Promise<unknown>;
  mandatoryBudgetPayments: (context: DailySettlementPhaseContext) => Promise<unknown>;
  scheduledBudgetPayments: (context: DailySettlementPhaseContext) => Promise<unknown>;
  territoryCapacityProjections: (context: DailySettlementPhaseContext) => Promise<unknown>;
  v5Capacity: (context: DailySettlementPhaseContext) => Promise<unknown>;
  v5TerritoryContainers: (context: DailySettlementPhaseContext) => Promise<unknown>;
  corporationDynamics: (context: DailySettlementPhaseContext) => Promise<unknown>;
  houseNeedsServices: (context: DailySettlementPhaseContext) => Promise<unknown>;
  perishableResourceDecay: (context: DailySettlementPhaseContext) => Promise<unknown>;
  housePolicyExecution: (context: DailySettlementPhaseContext) => Promise<unknown>;
  budgetDividendEligibility: (context: DailySettlementPhaseContext) => Promise<unknown>;
  patentExpirations: (context: DailySettlementPhaseContext) => Promise<unknown>;
  researchAndProgress: (context: DailySettlementPhaseContext) => Promise<unknown>;
  globalPrograms: (context: DailySettlementPhaseContext) => Promise<unknown>;
  publicProjects: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifecycle: (context: DailySettlementPhaseContext) => Promise<unknown>;
  postSuccessionAccessRefresh: (context: DailySettlementPhaseContext) => Promise<unknown>;
  financialStates: (context: DailySettlementPhaseContext) => Promise<unknown>;
  institutionDissolution: (context: DailySettlementPhaseContext) => Promise<unknown>;
  financialProjections: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rankingsSnapshot: (context: DailySettlementPhaseContext) => Promise<unknown>;
  endOfDaySnapshots: (context: DailySettlementPhaseContext) => Promise<unknown>;
};

const required = (
  id: string,
  order: number,
  shardMode: DailySettlementShardMode,
  execute: (context: DailySettlementPhaseContext) => Promise<unknown>,
): DailySettlementPhase => ({ id, order, shardMode, status: 'required', execute });

const deferred = (
  id: string,
  order: number,
  shardMode: DailySettlementShardMode,
  execute: (context: DailySettlementPhaseContext) => Promise<unknown>,
): DailySettlementPhase => ({ id, order, shardMode, status: 'deferred', execute });

/** The sole ordered definition of a daily settlement day close. */
export function createDailySettlementPhaseRegistry(
  handlers: DailySettlementPhaseHandlers,
): readonly DailySettlementPhase[] {
  return [
    required('v5_policy_activation', 4, 'all', handlers.v5PolicyActivation),
    required('succession_activation', 5, 'all', handlers.activateSuccessors),
    required('constitution_snapshots', 6, 'all', handlers.constitutionSnapshots),
    deferred('prepare_partitions', 10, 'all', handlers.preparePartitions),
    required('profile_rebuild', 20, 'owner-shards', handlers.rebuildProfiles),
    required('profile_settlement', 30, 'all', handlers.profileSettlement),
    required('patent_expirations', 45, 'all', handlers.patentExpirations),
    required('ip_license_billing', 65, 'all', handlers.ipLicenseBilling),
    required('life_maintenance', 70, 'all', handlers.lifeMaintenance),
    required('construction_completion', 72, 'owner-shards', handlers.constructionCompletion),
    required('territory_lease_settlement', 73, 'owner-shards', handlers.territoryLeaseSettlement),
    required('commons_dividend_settlement', 74, 'all', handlers.commonsDividendSettlement),
    required('building_settlement', 75, 'owner-shards', handlers.buildingSettlement),
    deferred('basic_levy', 76, 'all', handlers.basicLevy),
    required('corporation_income_tax', 90, 'all', handlers.corporationIncomeTax),
    required('public_tax_assessment', 91, 'owner-shards', handlers.publicTaxAssessment),
    required('tax_reconciliation', 92, 'all', handlers.taxReconciliation),
    required('global_bank', 100, 'all', handlers.globalBank),
    required('bank_health', 110, 'all', handlers.bankHealth),
    deferred('mandatory_budget_payments', 115, 'all', handlers.mandatoryBudgetPayments),
    deferred('scheduled_budget_payments', 116, 'all', handlers.scheduledBudgetPayments),
    required('territory_capacity_projections', 120, 'all', handlers.territoryCapacityProjections),
    required('v5_capacity_assessment', 121, 'all', handlers.v5Capacity),
    required('v5_territory_containers', 122, 'all', handlers.v5TerritoryContainers),
    required('corporation_dynamics', 125, 'all', handlers.corporationDynamics),
    required('house_needs_services', 126, 'owner-shards', handlers.houseNeedsServices),
    required('perishable_resource_decay', 127, 'owner-shards', handlers.perishableResourceDecay),
    required('research_and_progress', 128, 'all', handlers.researchAndProgress),
    required('global_programs', 129, 'all', handlers.globalPrograms),
    required('public_projects', 130, 'all', handlers.publicProjects),
    required('house_policy_execution', 132, 'owner-shards', handlers.housePolicyExecution),
    deferred('budget_dividend_eligibility', 135, 'all', handlers.budgetDividendEligibility),
    required('financial_states', 140, 'all', handlers.financialStates),
    required('lifecycle', 145, 'all', handlers.lifecycle),
    required('post_succession_access_refresh', 150, 'all', handlers.postSuccessionAccessRefresh),
    required('institution_dissolution', 155, 'all', handlers.institutionDissolution),
    required('financial_projections', 160, 'all', handlers.financialProjections),
    required('rankings_snapshot', 165, 'all', handlers.rankingsSnapshot),
    required('end_of_day_snapshots', 170, 'all', handlers.endOfDaySnapshots),
  ];
}
