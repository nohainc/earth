import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Audit Log and User-Visible History API', async () => {
  const port = 8996;
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

    // 1. Audit endpoint returns valid checks and history structure
    const auditRes = await fetch(`${baseUrl}/api/audit`);
    assert.equal(auditRes.status, 200);
    const auditData = await auditRes.json();
    assert.ok(auditData.ok);
    assert.ok(auditData.checks);
    assert.equal(typeof auditData.checks.balancesValid, 'boolean');

    // 2. History endpoint returns events array with safe public attributes
    const historyRes = await fetch(`${baseUrl}/api/history?limit=10`);
    assert.equal(historyRes.status, 200);
    const historyData = await historyRes.json();
    assert.ok(Array.isArray(historyData.events));

    // Verify sensitive data is never present in history
    for (const evt of historyData.events) {
      assert.equal(evt.passwordHash, undefined);
      assert.equal(evt.passwordSalt, undefined);
      assert.equal(evt.token, undefined);
      assert.equal(evt.recoveryKey, undefined);
    }

    // 3. History cannot be mutated or deleted through public endpoints (405 or 404 or 400)
    const postRes = await fetch(`${baseUrl}/api/history`, { method: 'POST' });
    assert.ok(postRes.status >= 400);

    const deleteRes = await fetch(`${baseUrl}/api/history`, { method: 'DELETE' });
    assert.ok(deleteRes.status >= 400);

  } finally {
    server.kill('SIGKILL');
  }
});
