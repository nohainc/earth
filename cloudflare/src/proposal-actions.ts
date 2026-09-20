import type { PostgresRepository } from './repository.ts';
import { validateInitiativeOutcome } from './initiative-outcomes.ts';
import { assertConstitutionalAmendableRule, validateConstitutionalRuleValue } from './v5-constitution.ts';
import { WORLD_CONDITION_EFFECTS } from './world-conditions.ts';
import { executeProposalFinancialAction } from './proposal-finance-actions.ts';
import type { EconomicMutationContext } from './settlement-barrier-postgres.ts';

export type ProposalActionContext = {
  repository: PostgresRepository;
  proposal: Record<string, unknown>;
  action: Record<string, unknown>;
  gameDay: number;
  economicContext?: EconomicMutationContext;
};

export interface ProposalActionHandler {
  actionType: string;
  version: number;
  validateCreation(action: Record<string, unknown>): void;
  validateExecution(context: ProposalActionContext): Promise<void>;
  execute?(context: ProposalActionContext): Promise<Record<string, unknown>>;
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
  execute: async ({ repository, proposal, action, gameDay, economicContext }) => {
    if (!economicContext) throw new Error('Financial proposal execution requires an economic mutation context');
    return executeProposalFinancialAction(repository, proposal, action, gameDay, economicContext);
  },
};

const discussionHandler: ProposalActionHandler = {
  actionType: 'discussion',
  version: 1,
  validateCreation: (action) => {
    const targetValue = action.targetValue;
    const hasTargetValue = targetValue && typeof targetValue === 'object'
      ? Object.keys(targetValue as Record<string, unknown>).length > 0
      : targetValue !== undefined && targetValue !== null;
    if (action.targetCategory || hasTargetValue) {
      throw new Error('Discussion proposals cannot contain an executable target');
    }
  },
  validateExecution: async () => undefined,
};

const constitutionAmendmentHandler: ProposalActionHandler = {
  actionType: 'CONSTITUTION_AMENDMENT',
  version: 1,
  validateCreation: (action) => {
    if (!Array.isArray(action.changes) || action.changes.length === 0) {
      throw new Error('Constitution amendment requires at least one rule change');
    }
    const seen = new Set<string>();
    for (const item of action.changes) {
      if (!item || typeof item !== 'object') throw new Error('Constitution amendment changes must be objects');
      const change = item as Record<string, unknown>;
      const ruleCode = String(change.ruleCode ?? '').trim();
      if (!ruleCode || seen.has(ruleCode)) throw new Error('Constitution amendment contains duplicate or missing rule codes');
      seen.add(ruleCode);
      const definition = assertConstitutionalAmendableRule(ruleCode);
      if (change.clearOverride === true) {
        if (definition.authorityModel !== 'EARTH_DEFAULT_CORPORATION_OVERRIDE') throw new Error('Only Earth-default Corporation overrides can be cleared');
        continue;
      }
      validateConstitutionalRuleValue(ruleCode, change.value);
    }
  },
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

const earthTechnologyFrontierHandler: ProposalActionHandler = {
  actionType: 'EARTH_TECHNOLOGY_FRONTIER',
  version: 1,
  validateCreation: (action) => requiredFields(action, ['domainId', 'generationNumber', 'effectiveFromGameDay'], 'Earth technology frontier action'),
  validateExecution: async ({ proposal }) => {
    if (proposal.subject_type !== 'EARTH' || proposal.subject_id !== null) throw new Error('Earth technology frontier requires an Earth proposal');
  },
};

const initiativeCreateHandler: ProposalActionHandler = {
  actionType: 'INITIATIVE_CREATE',
  version: 1,
  validateCreation: (action) => {
    requiredFields(action, ['initiativeType', 'name', 'initiativeDescription', 'fundingTargetUnits', 'fundingDeadlineGameDay', 'fundingModel', 'executionModel', 'matchingPolicy', 'outcome'], 'Initiative creation action');
    if (!['PROGRAM', 'PUBLIC_PROJECT', 'EMERGENCY', 'COMMONS'].includes(String(action.initiativeType))) throw new Error('Initiative type is invalid');
    validateInitiativeOutcome(action.outcome);
    if (action.physicalTarget !== undefined && (typeof action.physicalTarget !== 'object' || action.physicalTarget === null || Array.isArray(action.physicalTarget))) throw new Error('Initiative physical target must be an object');
    if ('beneficiaryType' in action || 'beneficiaryId' in action || 'recipientAccountId' in action) throw new Error('Initiative authority must be Earth or Corporation scope');
    for (const field of ['fundingTargetUnits', 'treasuryAuthorizedUnits', 'matchingCapUnits']) {
      if (action[field] !== undefined && !/^\d+$/.test(String(action[field]))) throw new Error(`${field} must be a non-negative integer snapshot`);
    }
    if (String(action.initiativeType) === 'PROGRAM') {
      if (action.executionModel !== 'TIMED_PROGRAM') throw new Error('Program initiatives require timed execution');
      if (!Number.isInteger(Number(action.executionDurationGameDays)) || Number(action.executionDurationGameDays) <= 0) throw new Error('Program initiatives require a positive execution duration');
      if (!['TIME', 'TIME_AND_RESOURCES'].includes(String(action.progressModel ?? 'TIME'))) throw new Error('Program initiatives require time-based progress');
    }
  },
  validateExecution: async ({ proposal, action }) => {
    if (!['EARTH', 'CORPORATION'].includes(String(proposal.subject_type))) throw new Error('Initiative proposal has an invalid governance scope');
    if (proposal.subject_type === 'CORPORATION' && !String(action.corporationId ?? proposal.subject_id ?? '').trim()) throw new Error('Corporation initiative requires a Corporation scope');
  },
};

function requiredFields(action: Record<string, unknown>, fields: string[], label: string): void {
  if (fields.some((field) => action[field] === undefined || action[field] === null || action[field] === '')) {
    throw new Error(`${label} requires ${fields.join(', ')}`);
  }
}

const legacyOperationalHandlers: ProposalActionHandler[] = [
  {
    actionType: 'ORGANIZATION_BUDGET_SPEND',
    version: 1,
    validateCreation: (action) => requiredFields(action, ['budgetLineId', 'amountUnits', 'destinationAccountId'], 'Budget action'),
    validateExecution: async () => undefined,
  },
  {
    actionType: 'PUBLIC_PROJECT',
    version: 1,
    validateCreation: (action) => requiredFields(action, ['projectId'], 'Public project action'),
    validateExecution: async () => undefined,
  },
  {
    actionType: 'RESEARCH_FUNDING',
    version: 1,
    validateCreation: (action) => requiredFields(action, ['projectId'], 'Research funding action'),
    validateExecution: async () => undefined,
  },
  {
    actionType: 'ORGANIZATION_TECHNOLOGY_ADOPTION',
    version: 1,
    validateCreation: (action) => requiredFields(action, ['generationId', 'adoptionCostUnits'], 'Technology adoption action'),
    validateExecution: async () => undefined,
  },
  {
    actionType: 'WORLD_CONDITION',
    version: 1,
    validateCreation: (action) => {
      requiredFields(action, ['conditionCode', 'title', 'description', 'effectType', 'targetKey', 'effectiveFromGameDay'], 'World condition action');
      const effectType = String(action.effectType);
      const scopeType = String(action.scopeType ?? '');
      const modifierBps = Number(action.modifierBps);
      const effectiveFrom = Number(action.effectiveFromGameDay);
      if (!WORLD_CONDITION_EFFECTS.includes(effectType as typeof WORLD_CONDITION_EFFECTS[number])) throw new Error('World condition effect is invalid');
      if (!['WORLD', 'TERRITORY', 'ORGANIZATION'].includes(scopeType) || (scopeType === 'WORLD' ? action.scopeId != null : !action.scopeId)) throw new Error('World condition scope is invalid');
      if (!Number.isInteger(modifierBps) || modifierBps < -5000 || modifierBps > 5000 || !Number.isInteger(effectiveFrom) || effectiveFrom < 1) throw new Error('World condition modifier or effective day is invalid');
      if (action.effectiveToGameDay != null && (!Number.isInteger(Number(action.effectiveToGameDay)) || Number(action.effectiveToGameDay) < effectiveFrom)) throw new Error('World condition end day is invalid');
    },
    validateExecution: async ({ gameDay, action }) => {
      if (Number(action.effectiveFromGameDay) < gameDay + 1) throw new Error('World condition must begin after governance execution');
    },
    execute: async ({ repository, proposal, action, gameDay }) => {
      const conditionId = `WORLD-COND-${String(proposal.id)}`;
      const effectiveToGameDay = action.effectiveToGameDay == null ? null : Number(action.effectiveToGameDay);
      const result = { conditionId, proposalId: String(proposal.id), effectiveFromGameDay: Number(action.effectiveFromGameDay), effectiveToGameDay };
      await repository.query(`INSERT INTO world_conditions
        (id, condition_code, title, description, source_type, source_id, scope_type, scope_id,
         effect_type, target_key, modifier_bps, effective_from_game_day, effective_to_game_day, rules_version)
        VALUES ($1,$2,$3,$4,'GOVERNANCE',$5,$6,$7,$8,$9,$10,$11,$12,'world-conditions-v1')
        ON CONFLICT (id) DO NOTHING`, [conditionId, String(action.conditionCode), String(action.title), String(action.description), String(proposal.id), String(action.scopeType), action.scopeId == null ? null : String(action.scopeId), String(action.effectType), String(action.targetKey).toUpperCase(), Number(action.modifierBps), result.effectiveFromGameDay, effectiveToGameDay]);
      await repository.query(`INSERT INTO governance_executions_v4
        (id, proposal_id, action_type, handler_version, status, result, correlation_id, executed_game_day)
        VALUES ($1,$2,'WORLD_CONDITION','world-condition-v1','EXECUTED',$3::JSONB,$4,$5)
        ON CONFLICT (proposal_id) DO UPDATE SET status = 'EXECUTED', result = EXCLUDED.result, executed_game_day = EXCLUDED.executed_game_day`, [`EXEC-${String(proposal.id)}`, String(proposal.id), JSON.stringify(result), `governance-execution:${String(proposal.id)}`, gameDay]);
      return result;
    },
  },
];

const amendRuleHandler: ProposalActionHandler = {
  actionType: 'amend_rule',
  version: 1,
  validateCreation: () => {
    throw new Error('Generic rule amendments are retired; submit a typed V5 Constitution amendment');
  },
  validateExecution: async () => {
    throw new Error('Generic rule amendments are retired; submit a typed V5 Constitution amendment');
  },
};

const handlers = new Map<string, ProposalActionHandler>([
  [discussionHandler.actionType, discussionHandler],
  [constitutionAmendmentHandler.actionType, constitutionAmendmentHandler],
  [constructCivicBuildingHandler.actionType, constructCivicBuildingHandler],
  [startResearchHandler.actionType, startResearchHandler],
  [earthTechnologyFrontierHandler.actionType, earthTechnologyFrontierHandler],
  [initiativeCreateHandler.actionType, initiativeCreateHandler],
  [amendRuleHandler.actionType, amendRuleHandler],
  ...legacyOperationalHandlers.map((handler) => [handler.actionType, handler] as const),
  ...Array.from(FINANCIAL_ACTIONS, (actionType) => [actionType, financialHandler] as const),
]);

export function proposalActionHandler(actionType: unknown): ProposalActionHandler {
  const normalized = String(actionType ?? '').trim();
  if (!normalized) throw new Error('Proposal action type is required');
  const handler = handlers.get(normalized);
  if (!handler) throw new Error(`Unregistered proposal action handler: ${normalized}`);
  return handler;
}

export function validateProposalActionSnapshot(action: Record<string, unknown>): ProposalActionHandler {
  const handler = proposalActionHandler(action.actionType);
  handler.validateCreation(action);
  return handler;
}

export function isFinancialProposalAction(actionType: unknown): boolean {
  return FINANCIAL_ACTIONS.has(String(actionType ?? ''));
}
