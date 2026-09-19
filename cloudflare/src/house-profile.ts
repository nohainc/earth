export interface HouseProfile {
  profileVersion: 'V5-HOUSE-PROFILE-1';
  identity: {
    id: string;
    name: string;
    motto: string | null;
    status: string;
    generation: number;
    createdAt: string;
  };
  currentHuman: {
    id: string;
    displayName: string;
    birthGameDay: number;
    ageYears: number;
    status: string;
    standing: string;
    finalLegacy: string;
  };
  affiliation: {
    corporationId: string;
    corporationName: string;
    joinedGameDay: number;
    status: string;
  } | null;
  succession: {
    successorName: string;
    registeredGameDay: number;
    status: string;
  } | null;
  successionPolicy: {
    fixedCostUnits: string;
    percentageCostBps: string;
    transitionDays: number;
    rulesVersion: string | null;
  };
  successionQuote: {
    houseWalletUnits: string;
    estimatedCostUnits: string;
    calculation: 'FIXED' | 'PERCENTAGE' | 'NONE';
    affordable: boolean;
  };
  lineage: Array<{
    humanId: string;
    displayName: string;
    generation: number;
    birthGameDay: number;
    deathGameDay: number | null;
    status: string;
    standing: string;
    finalLegacy: string;
    relationship: 'PREDECESSOR' | 'SUCCESSOR' | 'CURRENT' | 'UNLINKED';
    relatedHumanId: string | null;
    successionEventId: string | null;
    successionStatus: string | null;
    effectiveGameDay: number | null;
  }>;
  history: Array<{
    id: string;
    gameDay: number;
    gameMinute: number | null;
    category: string;
    eventType: string;
    title: string;
    subjectType: string | null;
    subjectId: string | null;
  }>;
  settlementProfile: {
    corporationId: string | null;
    residentialCapacityUnits: string;
    productiveCapacityUnits: string;
    totalCapacityUnits: string;
    activeBuildingCount: number;
    profileVersion: string;
    sourceGameDay: number;
    dirty: boolean;
  } | null;
  economics: {
    walletUnits: string;
    dynastyLegacyUnits: string;
  };
  generatedFrom: 'postgres-canonical-facts-v5';
}
