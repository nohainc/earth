import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { writeFileSync, unlinkSync, mkdirSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { verifyDeploymentConfig, stripJsonComments } from '../scripts/verify-deployment-config.mjs';
import { verifyDeploymentEndpoints } from '../scripts/verify-deployment-endpoints.mjs';
import { verifyCanary } from '../scripts/verify-canary.mjs';
import { runPreflightChecks } from '../scripts/promote-production.mjs';

test('Deployment Configuration and Route Conflict Verification', async (t) => {
  await t.test('production wrangler configs validate with zero conflicts and full coverage', () => {
    const report = verifyDeploymentConfig();
    assert.equal(report.status, 'VALID');
    assert.equal(report.conflicts.length, 0);
    assert.equal(report.errors.length, 0);
    assert.equal(report.coverage.rootAndLanding, true);
    assert.equal(report.coverage.appShellAndAssets, true);
    assert.equal(report.coverage.apiSurface, true);
    assert.equal(report.coverage.edgeEvents, true);
    assert.equal(report.coverage.healthChecks, true);
  });

  await t.test('detects duplicate route patterns claimed by multiple workers', () => {
    const tempDir = resolve('test/.tmp-deploy-conflict-1');
    mkdirSync(tempDir, { recursive: true });

    const worker1Path = resolve(tempDir, 'wrangler.worker1.jsonc');
    const worker2Path = resolve(tempDir, 'wrangler.worker2.jsonc');

    writeFileSync(
      worker1Path,
      JSON.stringify({
        name: 'worker-primary',
        routes: [{ pattern: 'earthuc.com/app/*', zone_name: 'earthuc.com' }],
      })
    );

    writeFileSync(
      worker2Path,
      JSON.stringify({
        name: 'worker-duplicate',
        routes: [{ pattern: 'earthuc.com/app/*', zone_name: 'earthuc.com' }],
      })
    );

    try {
      const report = verifyDeploymentConfig({
        configPaths: [worker1Path, worker2Path],
      });
      assert.equal(report.status, 'CONFLICT_DETECTED');
      const dupConflict = report.conflicts.find((c) => c.type === 'DUPLICATE_ROUTE_PATTERN');
      assert.ok(dupConflict);
      assert.equal(dupConflict.pattern, 'earthuc.com/app/*');
      assert.deepEqual(dupConflict.workers.sort(), ['worker-duplicate', 'worker-primary']);
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  await t.test('detects custom domain route shadowing across workers', () => {
    const tempDir = resolve('test/.tmp-deploy-conflict-2');
    mkdirSync(tempDir, { recursive: true });

    const staticWorkerPath = resolve(tempDir, 'wrangler.static.jsonc');
    const apiWorkerPath = resolve(tempDir, 'wrangler.api.jsonc');

    writeFileSync(
      staticWorkerPath,
      JSON.stringify({
        name: 'worker-static-apex',
        custom_domains: ['earthuc.com'],
      })
    );

    writeFileSync(
      apiWorkerPath,
      JSON.stringify({
        name: 'worker-api',
        routes: [{ pattern: 'earthuc.com/api/*', zone_name: 'earthuc.com' }],
      })
    );

    try {
      const report = verifyDeploymentConfig({
        configPaths: [staticWorkerPath, apiWorkerPath],
      });
      assert.equal(report.status, 'CONFLICT_DETECTED');
      const shadowConflict = report.conflicts.find((c) => c.type === 'CUSTOM_DOMAIN_ROUTE_SHADOWING');
      assert.ok(shadowConflict);
      assert.equal(shadowConflict.domain, 'earthuc.com');
      assert.equal(shadowConflict.customDomainWorker, 'worker-static-apex');
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  await t.test('detects zone name mismatches across workers', () => {
    const tempDir = resolve('test/.tmp-deploy-conflict-3');
    mkdirSync(tempDir, { recursive: true });

    const workerAPath = resolve(tempDir, 'wrangler.a.jsonc');
    const workerBPath = resolve(tempDir, 'wrangler.b.jsonc');

    writeFileSync(
      workerAPath,
      JSON.stringify({
        name: 'worker-a',
        routes: [{ pattern: 'earthuc.com/*', zone_name: 'earthuc.com' }],
      })
    );

    writeFileSync(
      workerBPath,
      JSON.stringify({
        name: 'worker-b',
        routes: [{ pattern: 'otherzone.io/api/*', zone_name: 'otherzone.io' }],
      })
    );

    try {
      const report = verifyDeploymentConfig({
        configPaths: [workerAPath, workerBPath],
      });
      assert.equal(report.status, 'CONFLICT_DETECTED');
      const zoneConflict = report.conflicts.find((c) => c.type === 'ZONE_MISMATCH');
      assert.ok(zoneConflict);
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });
});

test('Live Automated Deployment Endpoints Verification', async () => {
  const port = 8996;
  const env = {
    ...process.env,
    PORT: String(port),
    NODE_ENV: 'test',
    DATABASE_URL: '',
  };

  const server = spawn('node', ['server.js'], {
    env,
    stdio: 'ignore',
  });

  try {
    // Wait for server to start
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    // 1. Verify all 7 critical endpoints
    const report = await verifyDeploymentEndpoints(`http://127.0.0.1:${port}`);

    assert.equal(report.allPassed, true);
    assert.equal(report.probes.root, true, 'Root (/) probe must pass');
    assert.equal(report.probes.landing, true, 'Landing (/landing) probe must pass');
    assert.equal(report.probes.app, true, 'App shell (/app) probe must pass');
    assert.equal(report.probes.appMainDartJs, true, 'App runtime JS (/app/main.dart.js) probe must pass');
    assert.equal(report.probes.apiHealth, true, 'API health (/api/health) probe must pass');
    assert.equal(report.probes.apiAuthMe, true, 'Auth session (/api/auth/me) probe must pass');
    assert.equal(report.probes.edgeEvents, true, 'Edge events (/edge/events) probe must pass');
    assert.equal(report.errors.length, 0);

    // 2. Verify Canary suite passes with 7 endpoints
    const canary = await verifyCanary(`http://127.0.0.1:${port}`);
    assert.equal(canary.allPassed, true);
    assert.equal(canary.probes.root, true);
    assert.equal(canary.probes.landing, true);
    assert.equal(canary.probes.app, true);
    assert.equal(canary.probes.appMainDartJs, true);
    assert.equal(canary.probes.apiHealth, true);
    assert.equal(canary.probes.apiAuthMe, true);
    assert.equal(canary.probes.edgeEvents, true);

    // 3. Verify Preflight Promotion includes DeploymentConfig check
    const preflight = runPreflightChecks({ dryRun: true });
    assert.equal(preflight.checks.deploymentConfig, 'PASSED');
    assert.equal(preflight.status, 'PROMOTION_READY');

  } finally {
    server.kill('SIGKILL');
  }

  // 4. Verify failure handling for offline target
  const offlineReport = await verifyDeploymentEndpoints('http://127.0.0.1:9999', { timeoutMs: 500 });
  assert.equal(offlineReport.allPassed, false);
  assert.equal(offlineReport.probes.root, false);
  assert.equal(offlineReport.probes.apiHealth, false);
  assert.ok(offlineReport.errors.length > 0);
});
