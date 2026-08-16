import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { runPreflightChecks } from '../scripts/promote-production.mjs';
import { verifyCanary } from '../scripts/verify-canary.mjs';
import { executeRollback } from '../scripts/rollback-deployment.mjs';

test('Deployment Promotion, Canary Verification, and Rollback Safety', async () => {
  // 1. Test Preflight Checks
  const report = runPreflightChecks({ dryRun: true });
  assert.ok(report.timestamp);
  assert.equal(report.checks.schemaManifest, 'PASSED');
  assert.equal(report.checks.flutterAssets, 'PASSED');
  assert.equal(report.checks.wranglerDryRun, 'PASSED');
  assert.equal(report.status, 'PROMOTION_READY');

  // Verify no secrets exist in the report
  const rawReport = JSON.stringify(report);
  assert.equal(rawReport.includes('password'), false);
  assert.equal(rawReport.includes('token'), false);
  assert.equal(rawReport.includes('secret'), false);

  // 2. Test Canary Verification against local server
  const port = 8997;
  const env = {
    ...process.env,
    PORT: String(port),
    NODE_ENV: 'test',
    EARTH_READ_ONLY_MODE: 'true',
  };

  const server = spawn('node', ['server.js'], {
    env,
    stdio: 'ignore',
  });

  try {
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const canary = await verifyCanary(`http://127.0.0.1:${port}`);
    assert.equal(canary.probes.health, true);
    assert.equal(canary.probes.readiness, true);
    assert.equal(canary.probes.worldSnapshot, true);
    assert.equal(canary.probes.flutterShell, true);
    assert.equal(canary.allPassed, true);

  } finally {
    server.kill('SIGKILL');
  }

  // 3. Test Rollback Helper
  const rollbackNoArg = executeRollback(null);
  assert.equal(rollbackNoArg.status, 'SKIPPED');
});
