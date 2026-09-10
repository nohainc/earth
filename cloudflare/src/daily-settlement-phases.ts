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
  preparePartitions: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rebuildProfiles: (context: DailySettlementPhaseContext) => Promise<unknown>;
  profileSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifeMaintenance: (context: DailySettlementPhaseContext) => Promise<unknown>;
  basicLevy: (context: DailySettlementPhaseContext) => Promise<unknown>;
  buildingSettlement: (context: DailySettlementPhaseContext) => Promise<unknown>;
  buildingPatentLicenses: (context: DailySettlementPhaseContext) => Promise<unknown>;
  cityCorporateIncomeTax: (context: DailySettlementPhaseContext) => Promise<unknown>;
  globalBank: (context: DailySettlementPhaseContext) => Promise<unknown>;
  cityDynamics: (context: DailySettlementPhaseContext) => Promise<unknown>;
  patentExpirations: (context: DailySettlementPhaseContext) => Promise<unknown>;
  researchAndProgress: (context: DailySettlementPhaseContext) => Promise<unknown>;
  lifecycle: (context: DailySettlementPhaseContext) => Promise<unknown>;
  financialStates: (context: DailySettlementPhaseContext) => Promise<unknown>;
  institutionDissolution: (context: DailySettlementPhaseContext) => Promise<unknown>;
  rankingsSnapshot: (context: DailySettlementPhaseContext) => Promise<unknown>;
  endOfDaySnapshots: (context: DailySettlementPhaseContext) => Promise<unknown>;
};

/** The sole ordered definition of a daily settlement day close. */
export function createDailySettlementPhaseRegistry(
  handlers: DailySettlementPhaseHandlers,
): readonly DailySettlementPhase[] {
  return [
    { id: 'prepare_partitions', order: 10, shardMode: 'all', execute: handlers.preparePartitions },
    { id: 'profile_rebuild', order: 20, shardMode: 'owner-shards', execute: handlers.rebuildProfiles },
    { id: 'profile_settlement', order: 30, shardMode: 'all', execute: handlers.profileSettlement },
    { id: 'life_maintenance', order: 40, shardMode: 'all', execute: handlers.lifeMaintenance },
    { id: 'basic_levy', order: 50, shardMode: 'all', execute: handlers.basicLevy },
    { id: 'building_settlement', order: 60, shardMode: 'all', execute: handlers.buildingSettlement },
    { id: 'building_patent_licenses', order: 70, shardMode: 'all', execute: handlers.buildingPatentLicenses },
    { id: 'city_corporate_income_tax', order: 80, shardMode: 'all', execute: handlers.cityCorporateIncomeTax },
    { id: 'global_bank', order: 90, shardMode: 'all', execute: handlers.globalBank },
    { id: 'city_dynamics', order: 100, shardMode: 'all', execute: handlers.cityDynamics },
    { id: 'patent_expirations', order: 105, shardMode: 'all', execute: handlers.patentExpirations },
    { id: 'research_and_progress', order: 110, shardMode: 'all', execute: handlers.researchAndProgress },
    { id: 'lifecycle', order: 120, shardMode: 'all', execute: handlers.lifecycle },
    { id: 'financial_states', order: 130, shardMode: 'all', execute: handlers.financialStates },
    { id: 'institution_dissolution', order: 140, shardMode: 'all', execute: handlers.institutionDissolution },
    { id: 'rankings_snapshot', order: 150, shardMode: 'all', execute: handlers.rankingsSnapshot },
    { id: 'end_of_day_snapshots', order: 160, shardMode: 'all', execute: handlers.endOfDaySnapshots },
  ];
}
