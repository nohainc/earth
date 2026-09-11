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

const FINANCIAL_ACTIONS = new Set([
  'APPROVE_BUDGET', 'AMEND_BUDGET', 'AUTHORIZE_MAJOR_PROJECT', 'AUTHORIZE_GRANT',
  'CHANGE_TAX_CHARTER', 'TRANSFER_RESERVE', 'DECLARE_DIVIDEND', 'APPROVE_BAILOUT',
  'AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX',
  'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX',
]);

function financialSnapshotValue(action: Record<string, unknown>, key: string): unknown {
  if (action[key] !== undefined) return action[key];
  const target = action.targetValue;
  return target && typeof target === 'object' ? (target as Record<string, unknown>)[key] : undefined;
}

const financialHandler: ProposalActionHandler = {
  actionType: 'financial',
  version: 1,
  validateCreation: (action) => {
    const actionType = String(action.actionType ?? '');
    if (!FINANCIAL_ACTIONS.has(actionType)) throw new Error(`Unsupported financial proposal action: ${actionType}`);
    if (!financialSnapshotValue(action, 'categoryCode') && ['APPROVE_BUDGET', 'AMEND_BUDGET'].includes(actionType)) throw new Error(`${actionType} requires a category snapshot`);
    if (financialSnapshotValue(action, 'amountUnits') === undefined && ['AUTHORIZE_MAJOR_PROJECT', 'AUTHORIZE_GRANT', 'TRANSFER_RESERVE', 'DECLARE_DIVIDEND', 'APPROVE_BAILOUT'].includes(actionType)) throw new Error(`${actionType} requires an amount snapshot`);
    if (['AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX'].includes(actionType)) {
      for (const key of ['taxRuleId', 'baseVersionId', 'oldRateBps', 'newRateBps', 'taxBase', 'beneficiaryEconomicId', 'effectiveDay', 'scope', 'category']) {
        if (financialSnapshotValue(action, key) === undefined) throw new Error(`${actionType} requires ${key} in its immutable snapshot`);
      }
    }
  },
  validateExecution: async ({ action, gameDay }) => {
    const actionType = String(action.actionType ?? '');
    const amount = financialSnapshotValue(action, 'amountUnits');
    if (amount !== undefined && (typeof amount !== 'string' && typeof amount !== 'number' || BigInt(String(amount)) < 0n)) throw new Error(`${actionType} amount must be a non-negative integer`);
    if (['AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX'].includes(actionType)) {
      const rate = financialSnapshotValue(action, 'newRateBps');
      if (!Number.isInteger(Number(rate)) || Number(rate) < 0 || Number(rate) > 10000) throw new Error(`${actionType} newRateBps must be between 0 and 10000`);
      if (Number(financialSnapshotValue(action, 'effectiveDay')) < gameDay + 1) throw new Error(`${actionType} must take effect after the settlement day`);
    }
  },
};

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
  ...Array.from(FINANCIAL_ACTIONS, (actionType) => [actionType, financialHandler] as const),
]);

export function proposalActionHandler(actionType: unknown): ProposalActionHandler {
  return handlers.get(String(actionType || 'generic')) ?? genericHandler;
}

export function validateProposalActionSnapshot(action: Record<string, unknown>): ProposalActionHandler {
  const handler = proposalActionHandler(action.actionType);
  handler.validateCreation(action);
  return handler;
}

export function isFinancialProposalAction(actionType: unknown): boolean {
  return FINANCIAL_ACTIONS.has(String(actionType ?? ''));
}
