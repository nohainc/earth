import test from 'node:test';
import assert from 'node:assert/strict';
import {
  proposalActionHandler,
  validateProposalActionSnapshot,
} from '../cloudflare/src/proposal-actions.ts';

test('discussion proposals are explicit and cannot carry an executable target', () => {
  const handler = validateProposalActionSnapshot({ actionType: 'discussion', targetValue: {} });
  assert.equal(handler.actionType, 'discussion');
  assert.throws(
    () => validateProposalActionSnapshot({ actionType: 'discussion', targetCategory: 'tax', targetValue: {} }),
    /cannot contain an executable target/,
  );
});

test('unknown or missing proposal actions fail closed', () => {
  assert.throws(() => proposalActionHandler('generic'), /Unregistered proposal action handler/);
  assert.throws(() => proposalActionHandler(undefined), /action type is required/);
});
