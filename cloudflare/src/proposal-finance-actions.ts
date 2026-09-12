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
  if (['AMEND_TAX_RULE', 'SET_PERSONAL_INCOME_TAX', 'SET_CORPORATE_INCOME_TAX', 'SET_BASIC_LEVY', 'SET_MARKET_TRANSACTION_TAX'].includes(actionType)) {
    const taxRuleId = required(action, 'taxRuleId');
    const baseVersionId = required(action, 'baseVersionId');
    const oldRateBps = Number(required(action, 'oldRateBps'));
    const newRateBps = Number(required(action, 'newRateBps'));
    const taxBase = required(action, 'taxBase');
    const beneficiaryEconomicId = required(action, 'beneficiaryEconomicId');
    const effectiveDay = Number(required(action, 'effectiveDay'));
    const latest = await tx.query<{ id: string; tax_rule_id: string; rate_bps: number; tax_base_definition: string; beneficiary_economic_id: string }>(
      `SELECT id, tax_rule_id, rate_bps, tax_base_definition, beneficiary_economic_id::TEXT
       FROM tax_rule_versions
       WHERE tax_rule_id = $1
       ORDER BY version DESC
       LIMIT 1
       FOR UPDATE`, [taxRuleId],
    );
    const current = latest.rows[0];
    if (!current || current.id !== baseVersionId || current.tax_rule_id !== taxRuleId || Number(current.rate_bps) !== oldRateBps || current.tax_base_definition !== taxBase || current.beneficiary_economic_id !== beneficiaryEconomicId) {
      throw new Error('STALE_CONFLICT: tax rule no longer matches the proposal base version');
    }
    if (effectiveDay <= gameDay) throw new Error('Tax changes become effective on a future game day');
    const created = await tx.query<{ earth_create_tax_rule_version: string }>(
      'SELECT earth_create_tax_rule_version($1,$2,$3,$4,$5,$6,$7,$8) AS earth_create_tax_rule_version',
      [taxRuleId, required(action, 'scope').toUpperCase(), required(action, 'category'), newRateBps, taxBase, beneficiaryEconomicId, effectiveDay, String(proposal.id)],
    );
    return { ok: true, actionType, taxRuleId, baseVersionId, newVersionId: created.rows[0]?.earth_create_tax_rule_version, effectiveDay };
  }
  throw new Error(`${actionType} is typed but has no V2 executor yet`);
}
