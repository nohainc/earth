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

test('Constitution amendments use the shared typed action registry', () => {
  const handler = validateProposalActionSnapshot({
    actionType: 'CONSTITUTION_AMENDMENT',
    changes: [{ ruleCode: 'EARTH.TAX.BASIC_LEVY_RATE', value: 500 }],
  });
  assert.equal(handler.actionType, 'CONSTITUTION_AMENDMENT');
  assert.throws(
    () => validateProposalActionSnapshot({
      actionType: 'CONSTITUTION_AMENDMENT',
      changes: [{ ruleCode: 'EARTH.CAPACITY.BASE_RATE', clearOverride: true }],
    }),
    /overrides can be cleared/,
  );
});
