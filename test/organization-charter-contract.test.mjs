import test from 'node:test';
import assert from 'node:assert/strict';
import { charterPreset, validateOrganizationCharter } from '../cloudflare/src/organization-charter.ts';

test('organization charter presets are constitutionally valid', () => {
  for (const archetype of ['CORPORATION', 'COOPERATIVE', 'RESEARCH', 'PUBLIC_BODY']) {
    const charter = validateOrganizationCharter(charterPreset(archetype));
    assert.ok(charter.capabilities.includes('GOVERNANCE'));
  }
});

test('organization charter validation rejects undeclared territory authority', () => {
  assert.throws(() => validateOrganizationCharter({
    ...charterPreset('COOPERATIVE'),
    authorityLimits: { canOwnAssets: true, canGovernTerritory: true },
  }), /Territory authority/);
});
