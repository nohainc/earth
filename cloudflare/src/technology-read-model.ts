export type TechnologyEffect = {
  effectType: string;
  modifierFamily: string;
  targetType: string;
  targetKey: string;
  modifierBps: number | null;
};

export type TechnologyCatalogEntry = {
  id: string;
  code: string;
  name: string;
  category: string;
  description: string;
  researchCostUnits: string;
  researchPointsRequired: string;
  researchDurationGameDays: string;
  effects: TechnologyEffect[];
  prerequisites: string[];
  viewerStatus: 'AVAILABLE' | 'ACTIVE' | 'ADOPTED' | 'LOCKED' | string;
  accessSource: 'RESEARCHED' | 'LICENSED' | 'PUBLIC_DOMAIN' | 'GRANTED' | null;
};

export type CorporationResearchBudget = {
  authorizedUnits: string;
  committedUnits: string;
  spentUnits: string;
  availableUnits: string;
  status: string;
};

export type CorporationResearchProject = {
  id: string;
  targetType: 'TECHNOLOGY' | 'BUILDING_BLUEPRINT' | string;
  targetId: string;
  status: string;
  creditCostUnits: string;
  startedGameDay: number | null;
  progressBps: number;
  remainingGameDays: number;
  completionGameDay: number | null;
};

export type BuildingBlueprintResearch = CorporationResearchProject & {
  catalogId: string;
  familyCode: string;
  tier: number | null;
};

export type TechnologyFrontierDomain = {
  id: string;
  code: string;
  name: string;
  frontierGeneration: number;
  effectiveFromGameDay: number;
  nextGeneration: number | null;
  nextGenerationMinimumGameDay: number | null;
  corporationAccessibleGeneration: number | null;
  governanceStatus: 'CURRENT' | 'READY_FOR_GOVERNANCE' | 'NO_NEXT_GENERATION';
};

export type TechnologyWorkspace = {
  catalog: TechnologyCatalogEntry[];
  projects: CorporationResearchProject[];
  adoptedCodes: string[];
  researchBudget: CorporationResearchBudget | null;
  frontier: TechnologyFrontierDomain[];
};
