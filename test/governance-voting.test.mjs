import test from 'node:test';
import assert from 'node:assert/strict';
import { quoteBallot, resolveDelegationChain } from '../cloudflare/src/governance-voting.ts';

test('quadratic Voice is integer, non-transferable voting weight', () => {
  const quote = quoteBallot({ method: 'QUADRATIC_VOICE', voice: 4n, remainingVoice: 20n });
  assert.equal(quote.voiceCost, 16n);
  assert.equal(quote.effectiveWeight, 5n);
  assert.equal(quote.remainingVoice, 4n);
});

test('delegation chains resolve and loops are rejected', () => {
  assert.equal(resolveDelegationChain('A', new Map([['A', 'B'], ['B', 'C']])), 'C');
  assert.throws(() => resolveDelegationChain('A', new Map([['A', 'B'], ['B', 'A']])), /loop/);
});
