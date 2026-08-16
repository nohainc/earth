import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Data Privacy, Public Projection Redaction, and Retention Controls', async () => {
  const port = 8998;
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

    // 1. Verify Public Projections do not leak restricted fields
    const publicEndpoints = [
      '/api/health',
      '/api/world',
      '/api/world/activity',
      '/api/rankings',
      '/api/history',
      '/api/pantheon',
      '/api/market/history?product=energy',
    ];

    const restrictedKeys = [
      'password_hash',
      'passwordHash',
      'password_salt',
      'passwordSalt',
      'otp_secret',
      'otpSecret',
      'session_token',
      'sessionToken',
      'recovery_token',
      'recoveryToken',
      'sql',
      'stack',
    ];

    for (const endpoint of publicEndpoints) {
      const res = await fetch(`${baseUrl}${endpoint}`);
      assert.equal(res.status, 200, `${endpoint} should return 200`);
      const body = await res.json();
      const raw = JSON.stringify(body);

      for (const key of restrictedKeys) {
        assert.equal(
          raw.includes(`"${key}"`),
          false,
          `Endpoint ${endpoint} must never expose restricted key: ${key}`
        );
      }
    }

    // 2. Verify error responses never leak SQL or stack traces
    const errRes = await fetch(`${baseUrl}/api/nonexistent-boundary-check`);
    const errBody = await errRes.json();
    assert.equal(errBody.stack, undefined);
    assert.equal(errBody.sql, undefined);
    assert.ok(errBody.code);
    assert.ok(errBody.correlationId);

  } finally {
    server.kill('SIGKILL');
  }
});
