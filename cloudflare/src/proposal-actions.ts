import type { PostgresRepository } from './repository.ts';

export type ProposalActionContext = {
  repository: PostgresRepository;
  proposal: Record<string, unknown>;
  action: Record<string, unknown>;
  gameDay: number;
};

export interface ProposalActionHandler {
  actionType: string;
  version: number;
  validateCreation(action: Record<string, unknown>): void;
  validateExecution(context: ProposalActionContext): Promise<void>;
}

const genericHandler: ProposalActionHandler = {
  actionType: 'generic',
  version: 1,
  validateCreation: () => undefined,
  validateExecution: async () => undefined,
};

const constructCivicBuildingHandler: ProposalActionHandler = {
  actionType: 'construct_civic_building',
  version: 1,
  validateCreation: (action) => {
    if (!action.buildingCatalogId || !action.buildingType) throw new Error('Civic construction action requires a catalog snapshot');
  },
  validateExecution: async ({ proposal }) => {
    if (!proposal.institution_id) throw new Error('Civic construction action requires an institution');
  },
};

const startResearchHandler: ProposalActionHandler = {
  actionType: 'start_research',
  version: 1,
  validateCreation: (action) => {
    if (!action.researchProjectId && !action.buildingType) throw new Error('Research action requires a research snapshot');
  },
  validateExecution: async () => undefined,
};

const amendRuleHandler: ProposalActionHandler = {
  actionType: 'amend_rule',
  version: 1,
  validateCreation: (action) => {
    if (!action.targetCategory) throw new Error('Rule amendment requires a target category');
  },
  validateExecution: async () => undefined,
};

const handlers = new Map<string, ProposalActionHandler>([
  [genericHandler.actionType, genericHandler],
  [constructCivicBuildingHandler.actionType, constructCivicBuildingHandler],
  [startResearchHandler.actionType, startResearchHandler],
  [amendRuleHandler.actionType, amendRuleHandler],
]);

export function proposalActionHandler(actionType: unknown): ProposalActionHandler {
  return handlers.get(String(actionType || 'generic')) ?? genericHandler;
}

export function validateProposalActionSnapshot(action: Record<string, unknown>): ProposalActionHandler {
  const handler = proposalActionHandler(action.actionType);
  handler.validateCreation(action);
  return handler;
}
