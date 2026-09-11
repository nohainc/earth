import type { PostgresRepository } from './repository.ts';

export type DailySettlementShardMode = 'all' | 'owner-shards';

export type DailySettlementPhaseContext = {
  tx: PostgresRepository;
  day: number;
  shard?: number;
};

export type DailySettlementPhase = {
  id: string;
  order: number;
  shardMode: DailySettlementShardMode;
  execute: (context: DailySettlementPhaseContext) => Promise<unknown>;
};

export type DailySettlementPhaseHandlers = {
  activateSuccessors: (context: DailySettlementPhaseContext) => Promise<unknown>;
  preparePartitions: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rebuildProfiles: (context: DailySettlementPhaseContext) => Promise<unknown>;
  profileSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifeMaintenance: (context: DailySettlementPhaseContext) => Promise<unknown>;
  basicLevy: (context: DailySettlementPhaseContext) => Promise<unknown>;
  ipLicenseBilling: (context: DailySettlementPhaseContext) => Promise<unknown>;
  buildingSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  cityCorporateIncomeTax: (context: DailySettlementPhaseContext) => Promise<unknown>;
  globalBank: (context: DailySettlementPhaseContext) => Promise<unknown>;
  bankHealth: (context: DailySettlementPhaseContext) => Promise<unknown>;
  cityDynamics: (context: DailySettlementPhaseContext) => Promise<unknown>;
  budgetDividendEligibility: (context: DailySettlementPhaseContext) => Promise<unknown>;
  patentExpirations: (context: DailySettlementPhaseContext) => Promise<unknown>;
  researchAndProgress: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifecycle: (context: DailySettlementPhaseContext) => Promise<unknown>;
  postSuccessionAccessRefresh: (context: DailySettlementPhaseContext) => Promise<unknown>;
  financialStates: (context: DailySettlementPhaseContext) => Promise<unknown>;
  institutionDissolution: (context: DailySettlementPhaseContext) => Promise<unknown>;
  financialProjections: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rankingsSnapshot: (context: DailySettlementPhaseContext) => Promise<unknown>;
  endOfDaySnapshots: (context: DailySettlementPhaseContext) => Promise<unknown>;
};

/** The sole ordered definition of a daily settlement day close. */
export function createDailySettlementPhaseRegistry(
  handlers: DailySettlementPhaseHandlers,
): readonly DailySettlementPhase[] {
  return [
    { id: 'succession_activation', order: 5, shardMode: 'all', execute: handlers.activateSuccessors },
    { id: 'prepare_partitions', order: 10, shardMode: 'all', execute: handlers.preparePartitions },
    { id: 'profile_rebuild', order: 20, shardMode: 'owner-shards', execute: handlers.rebuildProfiles },
    { id: 'profile_settlement', order: 30, shardMode: 'all', execute: handlers.profileSettlement },
    { id: 'patent_expirations', order: 45, shardMode: 'all', execute: handlers.patentExpirations },
    { id: 'ip_license_billing', order: 65, shardMode: 'all', execute: handlers.ipLicenseBilling },
    { id: 'building_settlement', order: 70, shardMode: 'all', execute: handlers.buildingSettlement },
    { id: 'basic_levy', order: 75, shardMode: 'all', execute: handlers.basicLevy },
    { id: 'city_corporate_income_tax', order: 90, shardMode: 'all', execute: handlers.cityCorporateIncomeTax },
    { id: 'global_bank', order: 100, shardMode: 'all', execute: handlers.globalBank },
    { id: 'bank_health', order: 110, shardMode: 'all', execute: handlers.bankHealth },
    { id: 'life_maintenance', order: 115, shardMode: 'all', execute: handlers.lifeMaintenance },
    { id: 'city_dynamics', order: 120, shardMode: 'all', execute: handlers.cityDynamics },
    { id: 'research_and_progress', order: 126, shardMode: 'all', execute: handlers.researchAndProgress },
    { id: 'budget_dividend_eligibility', order: 130, shardMode: 'all', execute: handlers.budgetDividendEligibility },
    { id: 'financial_states', order: 140, shardMode: 'all', execute: handlers.financialStates },
    { id: 'lifecycle', order: 145, shardMode: 'all', execute: handlers.lifecycle },
    { id: 'post_succession_access_refresh', order: 150, shardMode: 'all', execute: handlers.postSuccessionAccessRefresh },
    { id: 'institution_dissolution', order: 155, shardMode: 'all', execute: handlers.institutionDissolution },
    { id: 'financial_projections', order: 160, shardMode: 'all', execute: handlers.financialProjections },
    { id: 'rankings_snapshot', order: 165, shardMode: 'all', execute: handlers.rankingsSnapshot },
    { id: 'end_of_day_snapshots', order: 170, shardMode: 'all', execute: handlers.endOfDaySnapshots },
  ];
}
