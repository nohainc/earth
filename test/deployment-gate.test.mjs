import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('production deployment is database-gated and fail-closed', () => {
  const workflow = fs.readFileSync('.github/workflows/deploy-api.yml', 'utf8');
  assert.doesNotMatch(workflow, /continue-on-error/);
  for (const step of ['db:verify:ci-provenance', 'db:backup:postgres', 'db:migrate:postgres', 'db:verify:manifest', 'db:verify:invariants', 'cf:check', 'db:verify:readiness', 'deploy:canary:verify', 'Post-deploy']) {
    assert.match(workflow, new RegExp(step.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `deployment gate includes ${step}`);
  }
});

test('readiness verification rejects non-200, unhealthy, or stale-schema deployments', () => {
  const source = fs.readFileSync('scripts/verify-readiness.mjs', 'utf8');
  assert.match(source, /response\.status, 200/);
  assert.match(source, /body\.ok, true/);
  assert.match(source, /body\.schemaVersion/);
  assert.match(source, /manifest\.migrationVersion/);
});
