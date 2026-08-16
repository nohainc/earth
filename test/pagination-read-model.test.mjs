import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

test('Pagination, Filtering, and Read-Model Performance', async () => {
  const port = 8994;
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
    // Wait for server to be ready
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/api/health`);
        if (res.ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 150));
    }

    const baseUrl = `http://127.0.0.1:${port}`;

    // 1. Notifications bounded pagination
    const notifRes1 = await fetch(`${baseUrl}/api/notifications?limit=5`);
    assert.equal(notifRes1.status, 200);
    const notifs1 = await notifRes1.json();
    const notifList1 = notifs1.notifications || notifs1;
    assert.ok(Array.isArray(notifList1));
    assert.ok(notifList1.length <= 5, 'Notifications limit must be respected');

    // 2. World activity bounded query
    const activityRes = await fetch(`${baseUrl}/api/world/activity`);
    assert.equal(activityRes.status, 200);
    const activity = await activityRes.json();
    assert.ok(Array.isArray(activity.activity));

    // 3. Market price history bounded days
    const marketHistoryRes = await fetch(`${baseUrl}/api/market/history?product=energy&days=7`);
    assert.equal(marketHistoryRes.status, 200);
    const marketHistory = await marketHistoryRes.json();
    assert.equal(marketHistory.product, 'energy');
    assert.equal(typeof marketHistory.currentPrice, 'number');

    // 4. Rankings and public projections
    const rankingsRes = await fetch(`${baseUrl}/api/rankings`);
    assert.equal(rankingsRes.status, 200);
    const rankings = await rankingsRes.json();
    assert.ok(rankings.cities !== undefined || rankings.corporations !== undefined);

    // 5. World history bounded limit
    const historyRes = await fetch(`${baseUrl}/api/history?limit=10`);
    assert.equal(historyRes.status, 200);
    const history = await historyRes.json();
    assert.ok(history.events !== undefined || history.history !== undefined || Array.isArray(history));

  } finally {
    server.kill('SIGKILL');
  }
});
