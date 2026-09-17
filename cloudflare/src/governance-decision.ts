export type OneHouseVoteDecision = {
  quorumMet: boolean;
  passed: boolean;
  turnout: number;
  decisiveVotes: number;
};

/** Shared constitutional one-House-one-vote semantics for V4 compatibility and V5. */
export function evaluateOneHouseVote(input: {
  support: number;
  oppose: number;
  abstain: number;
  electorateSize: number;
  quorumBps: number;
  approvalBps: number;
}): OneHouseVoteDecision {
  const support = Math.max(0, Math.trunc(input.support));
  const oppose = Math.max(0, Math.trunc(input.oppose));
  const abstain = Math.max(0, Math.trunc(input.abstain));
  const electorateSize = Math.max(0, Math.trunc(input.electorateSize));
  const turnout = support + oppose + abstain;
  const decisiveVotes = support + oppose;
  const quorumMet = electorateSize > 0 && turnout * 10_000 >= electorateSize * input.quorumBps;
  const passed = quorumMet && decisiveVotes > 0 && support > oppose && support * 10_000 >= decisiveVotes * input.approvalBps;
  return { quorumMet, passed, turnout, decisiveVotes };
}
