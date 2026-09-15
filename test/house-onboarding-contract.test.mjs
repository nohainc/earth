import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('House onboarding is canonical, versioned, and connected to registration and authenticated routes', () => {
  const migration = fs.readFileSync('db/migrations/019_house_onboarding_progress.sql', 'utf8');
  const auth = fs.readFileSync('cloudflare/src/auth-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/house-routes.ts', 'utf8');
  assert.match(migration, /onboarding_version/);
  assert.match(migration, /completed_milestones JSONB/);
  assert.match(auth, /house_onboarding_progress/);
  assert.match(routes, /\/api\/house\/onboarding/);
  assert.match(routes, /advanceHouseOnboarding/);
});

test('House onboarding exposes actionable canonical starter facts', () => {
  const onboarding = fs.readFileSync('cloudflare/src/house-onboarding-postgres.ts', 'utf8');
  assert.match(onboarding, /creditBalanceUnits/);
  assert.match(onboarding, /house_residencies/);
  assert.match(onboarding, /territory_capacity_state/);
  assert.match(onboarding, /actionRoute/);
  assert.match(onboarding, /generatedFrom: 'postgres-canonical-facts'/);
});
