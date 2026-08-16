import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (err) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    }).on('error', reject);
  });
}

test('Comprehensive Worker & API Endpoint Surface Validation', async () => {
  const port = 9015;
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
        const res = await fetchJson(`http://127.0.0.1:${port}/api/health`);
        if (res.status === 200) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. World and simulation endpoints
    const worldRes = await fetchJson(`${baseUrl}/api/world`);
    assert.equal(worldRes.status, 200);
    assert.ok(worldRes.body.clock);

    const catalogRes = await fetchJson(`${baseUrl}/api/production/catalog`);
    assert.equal(catalogRes.status, 200);
    assert.ok(Array.isArray(catalogRes.body));

    // 2. Events and audit streams
    const ownRes = await fetchJson(`${baseUrl}/api/ownership/events`);
    assert.equal(ownRes.status, 200);
    const memRes = await fetchJson(`${baseUrl}/api/membership/events`);
    assert.equal(memRes.status, 200);
    const authRes = await fetchJson(`${baseUrl}/api/governance/authority/events`);
    assert.equal(authRes.status, 200);

    // 3. Finance & Market
    const bookRes = await fetchJson(`${baseUrl}/api/market/book`);
    assert.equal(bookRes.status, 200);
    const historyRes = await fetchJson(`${baseUrl}/api/market/history?product=energy`);
    assert.equal(historyRes.status, 200);

    // 4. Governance & Pantheon
    const rankingsRes = await fetchJson(`${baseUrl}/api/rankings`);
    assert.equal(rankingsRes.status, 200);
    const pantheonRes = await fetchJson(`${baseUrl}/api/pantheon`);
    assert.equal(pantheonRes.status, 200);

    // 5. Invariant Audit
    const auditRes = await fetchJson(`${baseUrl}/api/audit`);
    assert.equal(auditRes.status, 200);
    assert.equal(auditRes.body.checks.balancesValid, true);

  } finally {
    server.kill('SIGKILL');
  }
});
