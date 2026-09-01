#!/usr/bin/env node
import 'dotenv/config';
import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { createServer } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const artifactsDir = join(projectRoot, '.test-artifacts');
const databaseUrl = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const headed = process.env.EARTH_UI_HEADED === 'true';
const ownedProcesses = [];

async function findOpenPort(configuredPort) {
  if (configuredPort) return Number(configuredPort);
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  await new Promise((resolve) => server.close(resolve));
  if (!address || typeof address === 'string') throw new Error('Unable to reserve a local test port.');
  return address.port;
}

async function fetchWithTimeout(url, timeoutMs = 2_000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function apiIsReady(apiUrl) {
  try {
    const response = await fetchWithTimeout(`${apiUrl}/api/health`);
    if (!response.ok) return false;
    const payload = await response.json();
    // A new isolated Worker has not necessarily received its first scheduled
    // heartbeat yet. For test startup, require the actual API and PostgreSQL
    // dependency to be reachable; the browser journey verifies application use.
    return payload?.checks?.database === true &&
      payload?.checks?.coreSchema === true &&
      payload?.checks?.postgresReachable === true;
  } catch {
    return false;
  }
}

async function startProcess(name, command, args, env, cwd = projectRoot) {
  await mkdir(artifactsDir, { recursive: true });
  const log = createWriteStream(join(artifactsDir, `${name}.log`));
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, ...env },
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.pipe(process.stdout);
  child.stdout.pipe(log);
  child.stderr.pipe(process.stderr);
  child.stderr.pipe(log);
  ownedProcesses.push({ child, log });
  child.once('exit', () => log.end());
  return child;
}

async function runCommand(name, command, args, env, cwd = projectRoot) {
  await mkdir(artifactsDir, { recursive: true });
  const log = createWriteStream(join(artifactsDir, `${name}.log`));
  const code = await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.pipe(process.stdout);
    child.stdout.pipe(log);
    child.stderr.pipe(process.stderr);
    child.stderr.pipe(log);
    child.once('error', reject);
    child.once('exit', (exitCode) => resolve(exitCode ?? 1));
  });
  await new Promise((resolve) => log.end(resolve));
  if (code !== 0) throw new Error(`${name} failed. See .test-artifacts/${name}.log.`);
}

async function waitFor(description, isReady, process) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (await isReady()) return;
    if (process?.exitCode !== null) {
      throw new Error(`${description} stopped before becoming ready. See .test-artifacts for its log.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`${description} did not become ready within 60 seconds. See .test-artifacts for its log.`);
}

async function stopOwnedProcesses() {
  await Promise.all(ownedProcesses.reverse().map(async ({ child, log }) => {
    if (child.exitCode === null) {
      const exited = new Promise((resolve) => child.once('exit', resolve));
      process.kill(-child.pid, 'SIGTERM');
      await Promise.race([exited, new Promise((resolve) => setTimeout(resolve, 5_000))]);
      if (child.exitCode === null) {
        process.kill(-child.pid, 'SIGKILL');
        await exited;
      }
    }
    log.end();
  }));
}

try {
  if (!process.env.EARTH_TEST_PASSWORD) {
    throw new Error('EARTH_TEST_PASSWORD is required. Configure it in an ignored .env file or CI secret store.');
  }

  const apiPort = await findOpenPort(process.env.EARTH_UI_API_PORT);
  const webPort = await findOpenPort(process.env.EARTH_UI_WEB_PORT);
  const apiUrl = `http://127.0.0.1:${apiPort}`;
  const webUrl = `http://127.0.0.1:${webPort}`;

  console.log(`Starting isolated local Worker API at ${apiUrl}`);
  const api = await startProcess('api', 'npx', [
    'wrangler', 'dev', '--test-scheduled', '--config', 'wrangler.api.jsonc',
    '--port', String(apiPort), '--ip', '127.0.0.1',
  ], {
    DATABASE_URL: databaseUrl,
    HYPERDRIVE_CONNECTION_STRING: databaseUrl,
    CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: databaseUrl,
    CORS_ORIGIN: webUrl,
  });
  await waitFor('Local Worker API', () => apiIsReady(apiUrl), api);

  console.log('Building isolated Flutter web client');
  await runCommand('flutter-build', 'flutter', [
    'build', 'web', `--dart-define=EARTH_API_URL=${apiUrl}`,
  ], {}, join(projectRoot, 'flutter_client'));

  console.log(`Starting isolated Flutter web client at ${webUrl}`);
  const web = await startProcess('flutter-web', 'npx', [
    'wrangler', 'pages', 'dev', 'flutter_client/build/web',
    '--port', String(webPort), '--ip', '127.0.0.1',
  ], {});
  await waitFor('Flutter web client', async () => {
    try { return (await fetchWithTimeout(webUrl)).ok; } catch { return false; }
  }, web);

  const args = ['playwright', 'test'];
  if (headed) args.push('--headed');
  const result = await new Promise((resolve, reject) => {
    const child = spawn('npx', args, {
      cwd: projectRoot,
      env: { ...process.env, EARTH_API_URL: apiUrl, EARTH_UI_URL: webUrl },
      stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('exit', (code) => resolve(code ?? 1));
  });
  process.exitCode = result;
} finally {
  await stopOwnedProcesses();
}
