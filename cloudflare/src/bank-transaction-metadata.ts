export type BankTransactionKind =
  | 'BANK_DEPOSIT_FUNDING'
  | 'BANK_DEPOSIT_PAYOUT'
  | 'BANK_LOAN_ORIGINATION'
  | 'BANK_LOAN_PAYMENT'
  | 'BANK_INTEREST_ACCRUAL'
  | 'BANK_DAILY_SETTLEMENT';

export type BankTransactionMetadata = {
  transactionKind: BankTransactionKind;
  sourceType: 'GLOBAL_BANK';
  sourceId: string;
  purpose: string;
  ruleVersion: 'global-bank-v2';
  actorType: 'SYSTEM';
  actorId: 'GLOBAL-BANK';
};

export function bankTransactionMetadata(transactionKind: BankTransactionKind, sourceId: string, purpose: string): BankTransactionMetadata {
  return { transactionKind, sourceType: 'GLOBAL_BANK', sourceId, purpose, ruleVersion: 'global-bank-v2', actorType: 'SYSTEM', actorId: 'GLOBAL-BANK' };
}

export const GLOBAL_BANK_DAILY_SETTLEMENT_METADATA = bankTransactionMetadata('BANK_DAILY_SETTLEMENT', 'GLOBAL-BANK', 'BANK_DAILY_SETTLEMENT');
