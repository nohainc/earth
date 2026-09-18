import type { PostgresRepository } from './repository.ts';
import { postEconomicTransaction } from './economic-transaction-postgres.ts';
import type { EconomicMutationContext } from './settlement-barrier-postgres.ts';

export type ProposalFundingResult = {
  configured: boolean;
  available: boolean;
  reason?: string;
  posted?: boolean;
};

/** Check every declared requirement and, when all are available, post them atomically to V2 sinks. */
export async function attemptProposalFunding(
  repository: PostgresRepository,
  proposalId: string,
  gameDay: number,
  context: EconomicMutationContext,
): Promise<ProposalFundingResult> {
  const requirements = await repository.query<{
    asset_id: number;
    required_units: string;
    source_account_id: string | null;
    source_balance: string | null;
    sink_account_id: string | null;
  }>(
    `SELECT r.asset_id, r.required_units, source.id::TEXT AS source_account_id,
            source.balance_units::TEXT AS source_balance, sink.id::TEXT AS sink_account_id
       FROM proposal_action_requirements r
       JOIN proposal_actions pa ON pa.id = r.proposal_action_id
       LEFT JOIN economic_accounts source
         ON source.owner_economic_id = r.source_owner_economic_id
        AND source.asset_id = r.asset_id
        AND source.account_type = r.source_account_type
        AND source.status = 'ACTIVE'
       LEFT JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
       LEFT JOIN economic_accounts sink
         ON sink.owner_economic_id = system_owner.economic_id
        AND sink.asset_id = r.asset_id
        AND sink.account_type = 'SYSTEM_ACCOUNT'
        AND sink.status = 'ACTIVE'
      WHERE pa.proposal_id = $1
      ORDER BY r.asset_id`,
    [proposalId],
  );
  if (!requirements.rows.length) return { configured: false, available: true };
  const missing = requirements.rows.find((row) => !row.source_account_id || !row.sink_account_id || BigInt(row.source_balance ?? '0') < BigInt(row.required_units));
  if (missing) return { configured: true, available: false, reason: `Insufficient ${missing.asset_id === 1 ? 'Credits' : 'resources'} for proposal action` };

  const entries = requirements.rows.flatMap((row) => [
    { account_id: row.source_account_id!, asset_id: row.asset_id, delta_units: (-BigInt(row.required_units)).toString(), reason_code: 'proposal_funding' },
    { account_id: row.sink_account_id!, asset_id: row.asset_id, delta_units: BigInt(row.required_units).toString(), reason_code: 'proposal_funding_sink' },
  ]);
  const result = await postEconomicTransaction(repository, {
    correlationId: `proposal-start:${proposalId}`,
    kind: 'ASSET_TRANSFER',
    sourceType: 'PROPOSAL',
    sourceId: proposalId,
    rulesVersion: 'economy-v2',
    entries,
  }, context);
  return { configured: true, available: true, posted: Boolean(result.transactionId) };
}
