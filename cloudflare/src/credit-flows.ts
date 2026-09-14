import type { PostgresRepository } from './repository.ts';
import { externalTransfer, type CreditSettlementContext, type CreditTransferResult } from './credit-settlement-postgres.ts';

type FlowContext = Omit<CreditSettlementContext, 'purpose'> & { purpose?: string };

function context(input: FlowContext, purpose: string): CreditSettlementContext {
  return { ...input, purpose };
}

export async function payHouseService(
  repository: PostgresRepository,
  input: { payerHouseId: string; providerHouseId: string; amount: string | number | bigint; context: FlowContext },
): Promise<CreditTransferResult> {
  if (input.payerHouseId === input.providerHouseId) throw new Error('House service payer and provider must differ');
  return externalTransfer(repository, {
    payer: { principalId: input.payerHouseId, accountPurpose: 'WALLET' },
    beneficiary: { principalId: input.providerHouseId, accountPurpose: 'WALLET' },
    amount: input.amount,
    context: context(input.context, input.context.purpose ?? 'HOUSE_SERVICE_PAYMENT'),
  });
}

export async function payCorporationGrant(
  repository: PostgresRepository,
  input: { corporationId: string; recipientHouseId: string; amount: string | number | bigint; context: FlowContext },
): Promise<CreditTransferResult> {
  return externalTransfer(repository, {
    payer: { principalId: input.corporationId, accountPurpose: 'TREASURY' },
    beneficiary: { principalId: input.recipientHouseId, accountPurpose: 'WALLET' },
    amount: input.amount,
    context: context(input.context, input.context.purpose ?? 'CORPORATION_GRANT'),
  });
}

export async function payEarthGrant(
  repository: PostgresRepository,
  input: { recipientId: string; recipientAccountPurpose: string; amount: string | number | bigint; context: FlowContext },
): Promise<CreditTransferResult> {
  return externalTransfer(repository, {
    payer: { principalId: 'EARTH', accountPurpose: 'TREASURY' },
    beneficiary: { principalId: input.recipientId, accountPurpose: input.recipientAccountPurpose },
    amount: input.amount,
    context: context(input.context, input.context.purpose ?? 'EARTH_GRANT'),
  });
}

export async function payCorporationDividend(
  repository: PostgresRepository,
  input: { corporationId: string; recipientHouseId: string; amount: string | number | bigint; context: FlowContext },
): Promise<CreditTransferResult> {
  return externalTransfer(repository, {
    payer: { principalId: input.corporationId, accountPurpose: 'TREASURY' },
    beneficiary: { principalId: input.recipientHouseId, accountPurpose: 'WALLET' },
    amount: input.amount,
    context: context(input.context, input.context.purpose ?? 'CORPORATION_DIVIDEND'),
  });
}

export async function payLicenseFee(
  repository: PostgresRepository,
  input: { licenseeId: string; licensorId: string; amount: string | number | bigint; licenseId: string; context: FlowContext; payerAccountPurpose?: string; beneficiaryAccountPurpose?: string },
): Promise<CreditTransferResult> {
  if (input.licenseeId === input.licensorId) throw new Error('Licensee and licensor must differ');
  return externalTransfer(repository, {
    payer: { principalId: input.licenseeId, accountPurpose: input.payerAccountPurpose ?? 'WALLET' },
    beneficiary: { principalId: input.licensorId, accountPurpose: input.beneficiaryAccountPurpose ?? 'OPERATIONS' },
    amount: input.amount,
    context: context({ ...input.context, reasonId: input.licenseId }, input.context.purpose ?? 'LICENSE_PAYMENT'),
  });
}
