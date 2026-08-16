import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { runBrowserE2E } from './browser-e2e-helper.mjs';

test('End-to-End Browser Testing against local server', async () => {
  const port = 8991;
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
    // Wait for server to start listening
    let ready = false;
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) {
          ready = true;
          break;
        }
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }
    assert.ok(ready, 'Local server started and is healthy');

    await runBrowserE2E(`http://127.0.0.1:${port}`);
  } finally {
    server.kill('SIGKILL');
  }
});
