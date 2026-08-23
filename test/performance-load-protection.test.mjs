import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Performance and Load Protection for Worker and PostgreSQL', async () => {
  const port = 9001;
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
    let sessionCookie = '';
    try {
      const loginRes = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: 'amara@earthuc.com', password: 'password123456' }),
      });
      sessionCookie = loginRes.headers.get('set-cookie')?.split(';')[0] || '';
    } catch {}

    const authHeaders = {
      'Content-Type': 'application/json',
      ...(sessionCookie ? { cookie: sessionCookie } : {}),
    };

    // 1. Measure latency for public read operations
    const start = performance.now();
    const worldRes = await fetch(`${baseUrl}/api/world`, { headers: authHeaders });
    const duration = performance.now() - start;
    assert.equal(worldRes.status, 200);
    assert.ok(duration < 500, `World read latency must stay within 500ms (got ${duration}ms)`);

    // 2. High-volume parallel read queries
    const readPromises = Array.from({ length: 20 }, () => fetch(`${baseUrl}/api/world/activity`));
    const readResponses = await Promise.all(readPromises);
    for (const r of readResponses) {
      assert.equal(r.status, 200);
    }

    // 3. Batch market orders under load
    const orderPromises = Array.from({ length: 10 }, (_, i) =>
      fetch(`${baseUrl}/api/market/orders`, {
        method: 'POST',
        headers: { ...authHeaders, 'Idempotency-Key': `load-order-${Date.now()}-${i}` },
        body: JSON.stringify({ product: 'energy', quantity: 1, limitPrice: 0.9, side: 'buy' }),
      })
    );
    const orderResponses = await Promise.all(orderPromises);
    for (const r of orderResponses) {
      assert.equal(r.status, 200);
    }

    // 4. Invariant audit confirmation under load
    const auditRes = await fetch(`${baseUrl}/api/audit`);
    const audit = await auditRes.json();
    assert.equal(audit.checks.balancesValid, true);

  } finally {
    server.kill('SIGKILL');
  }
});
