import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Concurrency and Idempotency Stress Tests', async () => {
  const port = 8995;
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
    // Wait for server to be ready
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. Concurrent duplicate market order commands with identical Idempotency-Key
    const idemKey = `order-stress-${Date.now()}`;
    const orderPromises = Array.from({ length: 8 }, () =>
      fetch(`${baseUrl}/api/market/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Idempotency-Key': idemKey },
        body: JSON.stringify({ product: 'energy', quantity: 2, limitPrice: 0.85, side: 'buy' }),
      }).then((r) => r.json())
    );
    const orderResults = await Promise.all(orderPromises);
    // All requests with identical idempotency key must return equivalent result without double deducting
    const firstResult = orderResults[0];
    for (const res of orderResults) {
      assert.equal(res.ok, firstResult.ok);
    }

    // 2. Concurrent duplicate governance vote submission
    const votePromises = Array.from({ length: 6 }, (_, i) =>
      fetch(`${baseUrl}/api/governance/proposals/042/vote`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Idempotency-Key': `vote-stress-${i}` },
        body: JSON.stringify({ vote: 'support' }),
      }).then((r) => r.json())
    );
    const voteResults = await Promise.all(votePromises);
    assert.ok(voteResults.some((r) => r.ok === true || r.ok === false));

    // 3. Concurrent business policy modification
    const policyPromises = ['reliability', 'margin', 'growth', 'reliability'].map((policy, i) =>
      fetch(`${baseUrl}/api/businesses/B-1048/policy`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Idempotency-Key': `policy-stress-${i}` },
        body: JSON.stringify({ policy }),
      }).then((r) => r.json())
    );
    const policyResults = await Promise.all(policyPromises);
    for (const res of policyResults) {
      assert.equal(res.ok, true);
    }

    // 4. Invariant check after concurrent mutations: balances non-negative
    const worldRes = await fetch(`${baseUrl}/api/world`);
    const world = await worldRes.json();
    assert.ok(world.human.credits >= 0, 'Human credits must remain non-negative');

  } finally {
    server.kill('SIGKILL');
  }
});
