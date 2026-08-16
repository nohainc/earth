import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Scheduler and Game-Time Recovery Controls', async () => {
  const port = 8999;
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

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. Check scheduler health diagnostics
    const healthRes = await fetch(`${baseUrl}/api/health`);
    assert.equal(healthRes.status, 200);
    const health = await healthRes.json();
    assert.ok(health.ok);
    assert.ok(health.checks);
    assert.equal(typeof health.checks.balancesNonNegative, 'boolean');

    // 2. Authoritative day advancement
    const tickKey = `sched-tick-${Date.now()}`;
    const advance1 = await fetch(`${baseUrl}/api/day/advance`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': tickKey },
    });
    assert.equal(advance1.status, 200);
    const result1 = await advance1.json();
    assert.ok(result1.ok);
    const initialDay = result1.state.clock.day;

    // 3. Replay with identical idempotency key produces identical result without re-advancing
    const advance2 = await fetch(`${baseUrl}/api/day/advance`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': tickKey },
    });
    assert.equal(advance2.status, 200);
    const result2 = await advance2.json();
    assert.equal(result2.state.clock.day, initialDay, 'Identical tickId must not double-advance game day');

    // 4. Invariant audit confirmation
    const auditRes = await fetch(`${baseUrl}/api/audit`);
    const audit = await auditRes.json();
    assert.equal(audit.checks.balancesValid, true);
    assert.equal(audit.checks.ledgerValid, true);

  } finally {
    server.kill('SIGKILL');
  }
});
