import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Flutter onboarding uses the authenticated server milestone API', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_onboarding.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/onboarding/house_onboarding_panel.dart', 'utf8');
  const commandCenter = fs.readFileSync('flutter_client/lib/features/command_center/command_center_screen.dart', 'utf8');
  assert.match(api, /\/api\/house\/onboarding/);
  assert.match(api, /expertSkip/);
  assert.match(panel, /HouseOnboardingState/);
  assert.match(panel, /btn-house-onboarding-advance/);
  assert.match(panel, /btn-house-onboarding-skip/);
  assert.match(commandCenter, /HouseOnboardingPanel/);
});
