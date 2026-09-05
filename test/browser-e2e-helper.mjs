import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';

async function findChromePath() {
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/google-chrome-stable',
  ];
  for (const path of candidates) {
    if (existsSync(path)) {
      try {
        const p = spawn(path, ['--version']);
        p.on('error', () => {});
        const code = await new Promise((resolve) => p.on('close', resolve));
        if (code === 0) return path;
      } catch {}
    }
  }
  return null;
}

async function stopChrome(chrome) {
  if (!chrome.killed) chrome.kill('SIGKILL');
  await Promise.race([
    new Promise((resolve) => chrome.once('close', resolve)),
    new Promise((resolve) => setTimeout(resolve, 2000)),
  ]);
}

async function removeProfile(profileDir) {
  await rm(profileDir, {
    recursive: true,
    force: true,
    maxRetries: 5,
    retryDelay: 200,
  });
}

export async function runBrowserE2E(baseUrl = 'http://127.0.0.1:8899') {
  const chromePath = await findChromePath();
  if (!chromePath) {
    console.log('Skipping browser tests: Chrome binary not found');
    return;
  }

  const port = 9333 + Math.floor(Math.random() * 500);
  // Chrome cannot safely share its default profile between concurrent test
  // processes. A dedicated profile also avoids first-run locks in GitHub CI.
  const profileDir = await mkdtemp(join(tmpdir(), 'earth-browser-e2e-'));
  let chromeOutput = '';
  const chrome = spawn(chromePath, [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    '--remote-debugging-address=127.0.0.1',
    `--user-data-dir=${profileDir}`,
    '--disable-gpu',
    '--disable-dev-shm-usage',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-default-apps',
    '--disable-extensions',
    '--disable-background-networking',
    '--disable-sync',
    '--mute-audio',
    '--no-sandbox',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  chrome.stderr?.on('data', (chunk) => {
    chromeOutput = `${chromeOutput}${chunk}`.slice(-2000);
  });

  // Wait for Chrome to be ready
  let wsUrl = null;
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) {
        const data = await res.json();
        wsUrl = data.webSocketDebuggerUrl;
        break;
      }
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }

  if (!wsUrl) {
    await stopChrome(chrome);
    await removeProfile(profileDir);
    throw new Error(`Chrome failed to start CDP debugger: ${chromeOutput || 'no diagnostic output'}`);
  }

  const browserWs = new WebSocket(wsUrl);
  await new Promise((r) => browserWs.on('open', r));

  let reqId = 1;
  const send = (ws, method, params = {}) => new Promise((resolve, reject) => {
    const id = reqId++;
    const handler = (data) => {
      const msg = JSON.parse(data);
      if (msg.id === id) {
        ws.off('message', handler);
        if (msg.error) reject(new Error(msg.error.message));
        else resolve(msg.result);
      }
    };
    ws.on('message', handler);
    ws.send(JSON.stringify({ id, method, params }));
  });

  try {
    // 1. Create target for landing page
    const { targetId } = await send(browserWs, 'Target.createTarget', { url: `${baseUrl}/` });
    const { sessionId } = await send(browserWs, 'Target.attachToTarget', { targetId, flatten: true });

    const sendSession = (method, params = {}) => new Promise((resolve, reject) => {
      const id = reqId++;
      const handler = (data) => {
        const msg = JSON.parse(data);
        if (msg.id === id) {
          browserWs.off('message', handler);
          if (msg.error) reject(new Error(msg.error.message));
          else resolve(msg.result);
        }
      };
      browserWs.on('message', handler);
      browserWs.send(JSON.stringify({ id, sessionId, method, params }));
    });

    const consoleMessages = [];
    const failedRequests = [];

    browserWs.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.sessionId === sessionId) {
        if (msg.method === 'Runtime.consoleAPICalled') {
          consoleMessages.push(msg.params);
        }
        if (msg.method === 'Network.responseReceived') {
          if (msg.params.response.status >= 400 && !msg.params.response.url.includes('favicon') && !msg.params.response.url.includes('/unauthorized')) {
            failedRequests.push({ url: msg.params.response.url, status: msg.params.response.status });
          }
        }
      }
    });

    await sendSession('Page.enable');
    await sendSession('Runtime.enable');
    await sendSession('Network.enable');

    // Test Landing Page
    await sendSession('Page.navigate', { url: `${baseUrl}/` });
    await new Promise((r) => setTimeout(r, 1000));

    const landingTitle = await sendSession('Runtime.evaluate', {
      expression: 'document.title',
      returnByValue: true,
    });
    assert.ok(landingTitle.result.value.includes('EARTH') || landingTitle.result.value.includes('United Corporations'), 'Landing page title should match EARTH');

    const landingUi = await sendSession('Runtime.evaluate', {
      expression: `({
        hasHero: document.querySelector('h1')?.textContent.includes('Build a future'),
        hasWorldLink: [...document.querySelectorAll('a')].some((a) => a.textContent.includes('The world')),
        themeToggles: (() => {
          const root = document.documentElement;
          const before = root.dataset.theme;
          document.querySelector('#theme')?.click();
          return before !== root.dataset.theme;
        })(),
      })`,
      returnByValue: true,
    });
    assert.equal(landingUi.result.value.hasHero, true, 'Landing page should render its primary hero heading');
    assert.equal(landingUi.result.value.hasWorldLink, true, 'Landing page should expose world navigation');
    assert.equal(landingUi.result.value.themeToggles, true, 'Landing page theme control should change the theme');

    // Test Flutter Web Application Load
    await sendSession('Page.navigate', { url: `${baseUrl}/app` });
    await new Promise((r) => setTimeout(r, 2000));

    const appTitle = await sendSession('Runtime.evaluate', {
      expression: 'document.title',
      returnByValue: true,
    });
    assert.ok(appTitle.result.value.includes('EARTH') || appTitle.result.value.includes('United Corporations'), 'Flutter web app title should match');

    const appUi = await sendSession('Runtime.evaluate', {
      expression: `({
        title: document.title,
        hasAppShell: Boolean(document.querySelector('.shell, flt-glass-pane, flutter-view, #earth-loading-container, [flt-renderer]')),
        bodyHasEarth: Boolean(document.body && (document.body.innerText.includes('EARTH') || document.body.innerHTML.includes('EARTH'))),
      })`,
      returnByValue: true,
    });
    assert.equal(appUi.result.value.hasAppShell, true, 'Application route should render an app shell');
    assert.equal(appUi.result.value.bodyHasEarth, true, 'Application route should render EARTH content');

    // Execute full end-to-end browser journeys inside the browser context
    const journeyEval = await sendSession('Runtime.evaluate', {
      expression: `(async () => {
        // 1. Health and Readiness
        const healthRes = await fetch('/api/health');
        const health = await healthRes.json();

        // 2. Authentication: Login Flow
        const loginRes = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'browser-login-1' },
          body: JSON.stringify({ email: 'amara@earthuc.com', password: 'password123456' })
        });
        const login = await loginRes.json();

        // 3. Current User / Session Check (Verify no credential leakage)
        const meRes = await fetch('/api/auth/me');
        const me = await meRes.json();

        // 4. Command Center / World Snapshot
        const worldRes = await fetch('/api/world');
        const world = await worldRes.json();

        // 5. Market Order Lifecycle
        const orderRes = await fetch('/api/market/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'browser-order-1' },
          body: JSON.stringify({ product: 'energy', quantity: 1, limitPrice: 0.90, side: 'buy' })
        });
        const order = await orderRes.json();

        // 6. Governance Vote with server-authoritative voting weight
        const voteRes = await fetch('/api/governance/proposals/042/vote', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'browser-vote-1' },
          body: JSON.stringify({ vote: 'support', weight: 999999 }) // spoofed weight ignored
        });
        const vote = await voteRes.json();

        // 7. AI Assistant Policy Modification
        const aiRes = await fetch('/api/ai/assistants/AI-01/policy', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'browser-ai-1' },
          body: JSON.stringify({ policy: 'maintenance', enabled: true })
        });
        const ai = await aiRes.json();

        // 8. Notifications Center
        const notifRes = await fetch('/api/notifications?limit=10');
        const notifs = await notifRes.json();

        // 9. Security: Verify Unauthorized / Bad Request returns safe error
        const unauthRes = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: 'nonexistent@earthuc.com', password: 'wrongpassword123' })
        });
        const unauth = await unauthRes.json();

        return {
          healthOk: health.ok === true,
          loginOk: login.ok === true && login.humanId === 'H-0044',
          credentialsNotExposed: login.passwordHash === undefined && login.sessionToken === undefined,
          meAuthenticated: me.authenticated === true && me.human?.id === 'H-0044',
          worldLoaded: Boolean(world && world.human && world.resources),
          orderPlaced: order.ok === true || order.status === 'placed',
          voteAccepted: vote.ok === true,
          voteWeightServerAuthoritative: vote.weight !== 999999,
          aiAccepted: ai.ok === true || ai.policy === 'maintenance',
          notificationsLoaded: Array.isArray(notifs.notifications || notifs),
          safeErrorReturned: unauth.ok === false && typeof unauth.error === 'string' && unauth.code !== undefined,
        };
      })()`,
      awaitPromise: true,
      returnByValue: true,
    });

    const results = journeyEval.result.value;
    assert.equal(results.healthOk, true, 'Health check should pass');
    assert.equal(results.loginOk, true, 'Login should succeed for valid credentials');
    assert.equal(results.credentialsNotExposed, true, 'Login response should never leak passwordHash or sessionToken');
    assert.equal(results.meAuthenticated, true, 'Session endpoint /api/auth/me should identify authenticated user');
    assert.equal(results.worldLoaded, true, 'World snapshot should load canonical human and resource data');
    assert.equal(results.orderPlaced, true, 'Market order should be accepted');
    assert.equal(results.voteAccepted, true, 'Governance vote should be accepted');
    assert.equal(results.voteWeightServerAuthoritative, true, 'Governance vote should reject client-forged weight');
    assert.equal(results.aiAccepted, true, 'AI policy update should be accepted');
    assert.equal(results.notificationsLoaded, true, 'Notifications should load successfully');
    assert.equal(results.safeErrorReturned, true, 'Invalid login should return safe error envelope without account leakage');

    // Close Target
    await send(browserWs, 'Target.closeTarget', { targetId });
    browserWs.close();
  } finally {
    await stopChrome(chrome);
    await removeProfile(profileDir);
  }
}
