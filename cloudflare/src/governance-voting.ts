export type VotingMethod = 'ONE_HOUSE_ONE_VOTE' | 'DELEGATED' | 'SHARE_WEIGHTED' | 'QUADRATIC_VOICE';

export type BallotQuote = { method: VotingMethod; baseWeight: bigint; effectiveWeight: bigint; voiceCost: bigint; remainingVoice: bigint };

export function quoteBallot(input: { method: VotingMethod; shareWeight?: bigint; voice?: bigint; remainingVoice?: bigint }): BallotQuote {
  const shareWeight = input.shareWeight ?? 1n;
  const voice = input.voice ?? 0n;
  const remainingVoice = input.remainingVoice ?? 0n;
  if (shareWeight < 0n || voice < 0n || remainingVoice < 0n) throw new Error('Voting quantities cannot be negative');
  if (input.method === 'SHARE_WEIGHTED') return { method: input.method, baseWeight: shareWeight, effectiveWeight: shareWeight, voiceCost: 0n, remainingVoice };
  if (input.method === 'QUADRATIC_VOICE') {
    const cost = voice * voice;
    if (cost > remainingVoice) throw new Error('Insufficient Voice');
    return { method: input.method, baseWeight: 1n, effectiveWeight: 1n + voice, voiceCost: cost, remainingVoice: remainingVoice - cost };
  }
  return { method: input.method, baseWeight: 1n, effectiveWeight: 1n, voiceCost: 0n, remainingVoice };
}

export function resolveDelegationChain(startHouseId: string, delegations: ReadonlyMap<string, string>): string {
  const seen = new Set<string>();
  let current = startHouseId;
  while (delegations.has(current)) {
    if (seen.has(current)) throw new Error('Delegation loop detected');
    seen.add(current);
    current = delegations.get(current)!;
  }
  return current;
}
