export type InitiativeMatchingPolicy = 'NONE' | 'LINEAR_MATCH' | 'BREADTH_MATCH';

export function calculateMatching(input: {
  contributionUnits: bigint;
  supporterCount: bigint;
  poolRemaining: bigint;
  targetRemaining: bigint;
  matchBps: bigint;
  policy?: InitiativeMatchingPolicy;
  breadthBonusBpsPerSupporter?: bigint;
  breadthSupporterCap?: bigint;
}): bigint {
  if (input.contributionUnits < 0n || input.supporterCount < 0n || input.poolRemaining < 0n || input.targetRemaining < 0n || input.matchBps < 0n) throw new Error('Matching quantities cannot be negative');
  const policy = input.policy ?? 'BREADTH_MATCH';
  if (policy === 'NONE') return 0n;
  const linear = (input.contributionUnits * input.matchBps) / 10000n;
  const breadthCap = input.breadthSupporterCap ?? 100n;
  const breadthBonus = 10000n + (input.supporterCount < breadthCap ? input.supporterCount : breadthCap) * (input.breadthBonusBpsPerSupporter ?? 0n);
  const raw = policy === 'LINEAR_MATCH' ? linear : (linear * breadthBonus) / 10000n;
  return raw < input.poolRemaining ? (raw < input.targetRemaining ? raw : input.targetRemaining) : (input.poolRemaining < input.targetRemaining ? input.poolRemaining : input.targetRemaining);
}
