import test from 'node:test';
import assert from 'node:assert/strict';
import {
  constitutionalInputSpec,
  getConstitutionalRuleDefinition,
  parseConstitutionalInputValue,
} from '../cloudflare/src/v5-constitution.ts';

test('Constitution amendment inputs convert player units at the server boundary', () => {
  assert.equal(
    parseConstitutionalInputValue('EARTH.CAPACITY.BASE_RATE', '12.50'),
    1250n,
  );
  assert.equal(
    parseConstitutionalInputValue('EARTH.GOVERNANCE.POLICY_QUORUM_BPS', '2.50'),
    250n,
  );
  assert.equal(
    parseConstitutionalInputValue('EARTH.GOVERNANCE.VOTING_PERIOD_DAYS', '7'),
    7n,
  );
  assert.throws(
    () => parseConstitutionalInputValue('EARTH.GOVERNANCE.POLICY_QUORUM_BPS', '250'),
    /100.00/,
  );
});

test('Constitution input specifications expose player units and constraints', () => {
  const credit = constitutionalInputSpec(
    getConstitutionalRuleDefinition('EARTH.CAPACITY.BASE_RATE'),
  );
  assert.deepEqual(
    { inputKind: credit.inputKind, min: credit.min, max: credit.max, step: credit.step },
    { inputKind: 'DECIMAL_CREDIT', min: '0.00', max: null, step: '0.01' },
  );
  const rate = constitutionalInputSpec(
    getConstitutionalRuleDefinition('EARTH.GOVERNANCE.POLICY_QUORUM_BPS'),
  );
  assert.deepEqual(
    { inputKind: rate.inputKind, min: rate.min, max: rate.max, step: rate.step },
    { inputKind: 'PERCENTAGE', min: '0.00', max: '100.00', step: '0.01' },
  );
});
