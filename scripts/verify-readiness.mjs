import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const target = (process.env.DEPLOY_URL || process.argv[2] || '').replace(/\/+$/, '');
if (!target) throw new Error('DEPLOY_URL or a deployment URL argument is required');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const MAX_ATTEMPTS = 6;
const RETRY_DELAY_MS = 5000;

let lastResponse;
let lastBody;

for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
  try {
    const response = await fetch(`${target}/api/ready`, { signal: AbortSignal.timeout(15000) });
    const body = await response.json().catch(() => ({}));
    lastResponse = response;
    lastBody = body;
    if (response.status === 200 && body.ok === true) {
      break;
    }
    console.log(`Readiness attempt ${attempt}/${MAX_ATTEMPTS}: status=${response.status}, ok=${body.ok}, checks=${JSON.stringify(body.checks)}`);
  } catch (err) {
    console.log(`Readiness attempt ${attempt}/${MAX_ATTEMPTS} error: ${err.message}`);
  }
  if (attempt < MAX_ATTEMPTS) {
    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
  }
}

const response = lastResponse;
const body = lastBody;

if (!response || response.status !== 200 || !body?.ok) {
  console.error('Readiness failure payload:', JSON.stringify(body, null, 2));
}

assert.ok(response, 'readiness endpoint could not be reached');
assert.equal(response.status, 200, `readiness returned ${response.status}`);
assert.equal(body.ok, true, 'readiness payload is not healthy');
assert.equal(body.schemaVersion, manifest.migrationVersion, 'deployed schema version is not current');
assert.equal(body.expectedSchemaVersion, manifest.migrationVersion, 'Worker expected schema version is not current');
console.log(JSON.stringify({ ok: true, target, schemaVersion: body.schemaVersion }));
