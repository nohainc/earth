import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Production Readiness Monitoring and Health Probes', async () => {
  const port = 8993;
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
    // Wait for server to be ready
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. Check /api/health and /api/ready
    for (const path of ['/api/health', '/health', '/api/ready', '/ready']) {
      const res = await fetch(`${baseUrl}${path}`);
      assert.equal(res.status, 200, `${path} should return 200`);
      const body = await res.json();
      assert.equal(body.ok, true);
      assert.ok(body.checks, 'Response should contain checks');
      assert.equal(typeof body.checks.balancesNonNegative, 'boolean');
      assert.equal(typeof body.checks.machineConditionsBounded, 'boolean');
      assert.equal(typeof body.checks.outboxPressure, 'boolean');
      assert.equal(typeof body.checks.outboxRetryFailures, 'boolean');
      assert.ok(body.readiness, 'Response should contain readiness details');
      assert.ok(body.readiness.outboxMetrics, 'Readiness should include outboxMetrics');
      assert.equal(typeof body.readiness.outboxMetrics.pendingCount, 'number');
      assert.equal(typeof body.readiness.outboxMetrics.retryCount, 'number');
      assert.equal(typeof body.readiness.outboxMetrics.staleLocksCount, 'number');
      assert.equal(typeof body.readiness.outboxMetrics.deadLetterCount, 'number');
    }

  } finally {
    server.kill('SIGKILL');
  }
});
