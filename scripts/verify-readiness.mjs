import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const target = (process.env.DEPLOY_URL || process.argv[2] || '').replace(/\/+$/, '');
if (!target) throw new Error('DEPLOY_URL or a deployment URL argument is required');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const response = await fetch(`${target}/api/ready`, { signal: AbortSignal.timeout(15000) });
const body = await response.json();
assert.equal(response.status, 200, `readiness returned ${response.status}`);
assert.equal(body.ok, true, 'readiness payload is not healthy');
assert.equal(body.schemaVersion, manifest.migrationVersion, 'deployed schema version is not current');
assert.equal(body.expectedSchemaVersion, manifest.migrationVersion, 'Worker expected schema version is not current');
console.log(JSON.stringify({ ok: true, target, schemaVersion: body.schemaVersion }));
