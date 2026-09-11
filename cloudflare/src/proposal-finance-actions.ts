import type { PostgresRepository } from './repository.ts';
import { setBudgetAuthorization } from './budget-authorization.ts';
import { approveInstitutionGrant } from './institution-grants.ts';
import { spendInstitutionBudget } from './institution-spending.ts';

function payload(action: Record<string, unknown>, key: string): unknown {
  if (action[key] !== undefined) return action[key];
  const target = action.targetValue;
  return target && typeof target === 'object' ? (target as Record<string, unknown>)[key] : undefined;
}

function required(action: Record<string, unknown>, key: string): string {
  const value = payload(action, key);
  if (value === undefined || value === null || value === '') throw new Error(`Financial proposal action requires ${key}`);
  return String(value);
}

/** Delegates proposal execution to the existing Budget V2 services. */
export async function executeProposalFinancialAction(
  tx: PostgresRepository,
  proposal: Record<string, unknown>,
  action: Record<string, unknown>,
  gameDay: number,
): Promise<Record<string, unknown>> {
  const actionType = String(action.actionType ?? '');
  const institutionId = String(proposal.institution_id ?? required(action, 'institutionId'));
  if (actionType === 'APPROVE_BUDGET' || actionType === 'AMEND_BUDGET') {
    return setBudgetAuthorization(tx, {
      institutionId,
      institutionKind: required(action, 'institutionKind').toUpperCase(),
      fiscalPeriodId: required(action, 'fiscalPeriodId'),
      categoryCode: required(action, 'categoryCode').toUpperCase(),
      authorizedUnits: BigInt(required(action, 'amountUnits')),
      createdGameDay: gameDay,
      ruleVersion: required(action, 'rulesVersion'),
    });
  }
  if (actionType === 'AUTHORIZE_GRANT') {
    return approveInstitutionGrant(tx, {
      grantorInstitutionId: institutionId,
      recipientInstitutionId: required(action, 'recipientInstitutionId'),
      budgetLineId: required(action, 'budgetLineId'),
      amountUnits: BigInt(required(action, 'amountUnits')),
      grantType: required(action, 'grantType'),
      correlationId: `proposal-grant:${String(proposal.id)}:1`,
      gameDay,
    });
  }
  if (actionType === 'TRANSFER_RESERVE') {
    const amountUnits = BigInt(required(action, 'amountUnits'));
    return spendInstitutionBudget(tx, {
      institutionId,
      budgetLineId: required(action, 'budgetLineId'),
      sourceAccountId: required(action, 'sourceAccountId'),
      recipientAccountId: required(action, 'recipientAccountId'),
      amountUnits,
      purpose: 'PROPOSAL_TRANSFER_RESERVE',
      sourceType: 'proposal_action',
      sourceId: String(proposal.id),
      correlationId: `proposal-reserve:${String(proposal.id)}:1`,
      gameDay,
      commitmentId: payload(action, 'commitmentId') ? String(payload(action, 'commitmentId')) : undefined,
    });
  }
  throw new Error(`${actionType} is typed but has no V2 executor yet`);
}
