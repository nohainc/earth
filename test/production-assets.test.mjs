import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('production Flutter assets are executable JavaScript and readiness aliases are JSON', async () => {
  let baseUrl = process.env.EARTH_REMOTE_URL;
  let localServer = null;

  if (!baseUrl) {
    const port = 9100 + Math.floor(Math.random() * 800);
    localServer = spawn('node', ['server.js'], {
      env: { ...process.env, PORT: String(port), NODE_ENV: 'test', DATABASE_URL: '' },
      stdio: 'ignore',
    });
    baseUrl = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let i = 0; i < 40; i++) {
      try {
        const res = await fetch(`${baseUrl}/api/health`);
        if (res.ok) {
          ready = true;
          break;
        }
      } catch {}
      await new Promise((r) => setTimeout(r, 100));
    }
    assert.ok(ready, 'Local server failed to start');
  }

  try {
    for (const path of ['/app/flutter_bootstrap.js', '/flutter_bootstrap.js']) {
      const response = await fetch(`${baseUrl}${path}`);
      const body = await response.text();
      assert.equal(response.status, 200, `${path} should be available`);
      assert.match(response.headers.get('content-type') || '', /javascript|ecmascript/i, `${path} must not be an HTML fallback`);
      assert.doesNotMatch(body.slice(0, 200), /<!doctype html>|<html/i, `${path} must contain JavaScript`);
    }

    for (const path of ['/api/ready', '/health', '/ready']) {
      const response = await fetch(`${baseUrl}${path}`);
      const contentType = response.headers.get('content-type') || '';
      assert.equal(response.status, 200, `${path} should be available`);
      assert.match(contentType, /application\/json/i, `${path} should return JSON readiness data`);
      const body = await response.json();
      assert.ok(body.status || body.ok, `${path} should expose readiness status`);
    }
  } finally {
    if (localServer) localServer.kill('SIGKILL');
  }
});
