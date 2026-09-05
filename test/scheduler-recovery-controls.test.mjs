import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Scheduler and Game-Time Recovery Controls', async () => {
  const port = 8999;
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
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. Check scheduler health diagnostics
    const healthRes = await fetch(`${baseUrl}/api/health`);
    assert.equal(healthRes.status, 200);
    const health = await healthRes.json();
    assert.ok(health.ok);
    assert.ok(health.checks);
    assert.equal(typeof health.checks.balancesNonNegative, 'boolean');

    // 4. Invariant audit confirmation
    const auditRes = await fetch(`${baseUrl}/api/audit`);
    const audit = await auditRes.json();
    assert.equal(audit.checks.balancesValid, true);
    assert.equal(audit.checks.ledgerValid, true);

  } finally {
    server.kill('SIGKILL');
  }
});
