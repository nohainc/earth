import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Tier 5: Comprehensive End-to-End Player Journey (Register -> Trade -> Operate -> Vote -> Logout)', async () => {
  const port = 9015;
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
    // 1. Wait for server health readiness
    let ready = false;
    for (let i = 0; i < 40; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) {
          ready = true;
          break;
        }
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }
    assert.ok(ready, 'Server must start and report healthy');

    const baseUrl = `http://127.0.0.1:${port}`;
    const founderEmail = `founder_${Date.now()}@earthuc.com`;
    const password = 'Password123456';

    // 2. Register new Founder
    const registerRes = await fetch(`${baseUrl}/api/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: founderEmail,
        password,
        passwordConfirmation: password,
        displayName: 'Vance Executive',
      }),
    });
    assert.equal(registerRes.status, 201, 'Registration must succeed with 201');
    const registerJson = await registerRes.json();
    assert.equal(registerJson.ok, true);

    // 3. Login to establish authenticated session
    const loginRes = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: founderEmail, password }),
    });
    assert.equal(loginRes.status, 200, 'Login must succeed');
    const sessionCookie = loginRes.headers.get('set-cookie')?.split(';')[0] || '';
    assert.ok(sessionCookie.length > 0, 'Session cookie must be provided');

    const authHeaders = {
      'Content-Type': 'application/json',
      cookie: sessionCookie,
    };

    // 4. Query authoritative World State and Player Human
    const worldRes = await fetch(`${baseUrl}/api/world`, { headers: authHeaders });
    assert.equal(worldRes.status, 200);
    const world = await worldRes.json();
    assert.ok(world.human, 'Authenticated player must have human entity');
    assert.ok(world.human.credits > 0, 'Starter credits must be funded');

    // 5. Execute Market Order on Central Exchange
    const orderRes = await fetch(`${baseUrl}/api/market/orders`, {
      method: 'POST',
      headers: { ...authHeaders, 'Idempotency-Key': `e2e-order-${Date.now()}` },
      body: JSON.stringify({
        product: 'energy',
        quantity: 2,
        limitPrice: 1.5,
        side: 'buy',
      }),
    });
    assert.equal(orderRes.status, 200);
    const orderJson = await orderRes.json();
    assert.equal(orderJson.ok, true);

    // 6. Update Corporate Operational Policy
    const policyRes = await fetch(`${baseUrl}/api/businesses/B-1048/policy`, {
      method: 'POST',
      headers: { ...authHeaders, 'Idempotency-Key': `e2e-policy-${Date.now()}` },
      body: JSON.stringify({ policy: 'growth' }),
    });
    assert.equal(policyRes.status, 200);
    const policyJson = await policyRes.json();
    assert.equal(policyJson.ok, true);

    // 7. Cast Civic Vote on Governance Proposal
    const voteRes = await fetch(`${baseUrl}/api/governance/proposals/042/vote`, {
      method: 'POST',
      headers: { ...authHeaders, 'Idempotency-Key': `e2e-vote-${Date.now()}` },
      body: JSON.stringify({ vote: 'support' }),
    });
    assert.equal(voteRes.status, 200);
    const voteJson = await voteRes.json();
    assert.equal(voteJson.ok, true);

    // 8. Confirm Audit Log & Invariant Integrity
    const auditRes = await fetch(`${baseUrl}/api/audit`);
    assert.equal(auditRes.status, 200);
    const audit = await auditRes.json();
    assert.equal(audit.checks.balancesValid, true);

    // 9. Logout
    const logoutRes = await fetch(`${baseUrl}/api/auth/logout`, {
      method: 'POST',
      headers: authHeaders,
    });
    assert.equal(logoutRes.status, 200);
    const logoutJson = await logoutRes.json();
    assert.equal(logoutJson.ok, true);

  } finally {
    server.kill('SIGKILL');
  }
});
