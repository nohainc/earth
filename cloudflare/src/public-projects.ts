export function calculateMatching(input: { contributionUnits: bigint; supporterCount: bigint; poolRemaining: bigint; targetRemaining: bigint; matchBps: bigint }): bigint {
  if (input.contributionUnits < 0n || input.supporterCount < 0n || input.poolRemaining < 0n || input.targetRemaining < 0n || input.matchBps < 0n) throw new Error('Matching quantities cannot be negative');
  const breadthBonus = input.supporterCount > 100n ? 10000n : 10000n + input.supporterCount * 25n;
  const raw = (input.contributionUnits * input.matchBps * breadthBonus) / 100000000n;
  return raw < input.poolRemaining ? (raw < input.targetRemaining ? raw : input.targetRemaining) : (input.poolRemaining < input.targetRemaining ? input.poolRemaining : input.targetRemaining);
}
