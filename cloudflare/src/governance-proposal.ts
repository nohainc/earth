export type GovernanceProposalSubjectType = 'EARTH' | 'CORPORATION';

export type GovernanceProposal = {
  identity: { id: string; title: string; body: string | null };
  scope: { subjectType: GovernanceProposalSubjectType; subjectId: string | null; subjectName: string };
  action: { actionType: string; category: string; payload: Record<string, unknown>; impactSummary: string | null; impact: Record<string, unknown> | null };
  status: { status: string; submittedGameDay: number; votingStartGameDay: number; votingEndGameDay: number; effectiveGameDay: number; executedGameDay: number | null; quorumMet: boolean | null };
  electorate: { electorateSize: number; quorumBps: number; quorumRequired: number; approvalBps: number };
  votes: { support: number; oppose: number; abstain: number; uncast: number; participationBps: number; decisiveApprovalBps: number };
  viewer: { eligible: boolean; canVote: boolean; voted: boolean; choice: string | null };
  governancePolicy: { rulesVersion: string | null; quorumBps: number; approvalBps: number; votingPeriodDays: number; implementationDelayDays: number };
};

function integer(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : fallback;
}

function category(actionType: string): string {
  if (actionType === 'CONSTITUTION_AMENDMENT') return 'CONSTITUTION';
  if (actionType === 'INITIATIVE_CREATE') return 'INITIATIVE';
  if (actionType.includes('CONSTRUCTION')) return 'CONSTRUCTION';
  if (actionType.includes('RESEARCH') || actionType.includes('TECHNOLOGY')) return 'RESEARCH';
  return 'POLICY';
}

export function governanceProposalFromRow(row: Record<string, unknown>): GovernanceProposal {
  const actionType = String(row.action_type ?? 'UNKNOWN');
  const payload = row.payload && typeof row.payload === 'object' ? row.payload as Record<string, unknown> : {};
  const policy = row.governance_rule_snapshot && typeof row.governance_rule_snapshot === 'object'
    ? row.governance_rule_snapshot as Record<string, unknown>
    : {};
  const electorateSize = integer(row.electorate_size);
  const support = integer(row.support_votes);
  const oppose = integer(row.oppose_votes);
  const abstain = integer(row.abstain_votes);
  const cast = support + oppose + abstain;
  const uncast = Math.max(0, electorateSize - cast);
  const subjectType = row.subject_type === 'CORPORATION' ? 'CORPORATION' : 'EARTH';
  const subjectId = row.subject_id == null ? null : String(row.subject_id);
  const status = String(row.status ?? 'VOTING');
  const quorumBps = integer(row.quorum_bps ?? policy.quorumBps);
  const approvalBps = integer(row.approval_bps ?? policy.approvalBps);
  const currentQuorumMet = electorateSize > 0 && cast * 10000 >= electorateSize * quorumBps;
  return {
    identity: { id: String(row.id), title: String(row.title ?? 'V5 governance proposal'), body: row.body == null ? null : String(row.body) },
    scope: { subjectType, subjectId, subjectName: String(row.subject_name ?? (subjectType === 'EARTH' ? 'EARTH' : subjectId ?? 'Corporation')) },
    action: { actionType, category: category(actionType), payload, impactSummary: row.impact_summary == null ? null : String(row.impact_summary), impact: payload.impact && typeof payload.impact === 'object' ? payload.impact as Record<string, unknown> : null },
    status: { status, submittedGameDay: integer(row.submitted_game_day), votingStartGameDay: integer(row.voting_start_game_day), votingEndGameDay: integer(row.voting_end_game_day), effectiveGameDay: integer(row.effective_from_game_day), executedGameDay: row.executed_game_day == null ? null : integer(row.executed_game_day), quorumMet: row.quorum_met == null ? currentQuorumMet : row.quorum_met === true },
    electorate: { electorateSize, quorumBps, quorumRequired: integer(row.quorum_required), approvalBps },
    votes: { support, oppose, abstain, uncast, participationBps: electorateSize > 0 ? Math.floor(cast * 10000 / electorateSize) : 0, decisiveApprovalBps: support + oppose > 0 ? Math.floor(support * 10000 / (support + oppose)) : 0 },
    viewer: { eligible: row.viewer_eligible !== false, canVote: row.viewer_can_vote === true, voted: row.viewer_voted === true, choice: row.viewer_choice == null ? null : String(row.viewer_choice) },
    governancePolicy: { rulesVersion: row.rules_version == null ? null : String(row.rules_version), quorumBps: integer(policy.quorumBps ?? quorumBps), approvalBps: integer(policy.approvalBps ?? approvalBps), votingPeriodDays: integer(policy.votingPeriodDays), implementationDelayDays: integer(policy.implementationDelayDays) },
  };
}
