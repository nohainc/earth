import { readFile } from 'node:fs/promises';

const wrangler = await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8');
const workerTypes = await readFile(new URL('../worker-configuration.d.ts', import.meta.url), 'utf8');
const repository = await readFile(new URL('../cloudflare/src/repository.ts', import.meta.url), 'utf8');
const worker = await readFile(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');

if (/d1_databases|"DB"\s*:/.test(wrangler)) throw new Error('D1 bindings must not be configured for EARTH');
if (!wrangler.includes('"PERSISTENCE_AUTHORITY": "postgres"')) throw new Error('PostgreSQL authority must be configured');
if (!wrangler.includes('"binding": "HYPERDRIVE"')) throw new Error('Hyperdrive binding is required');
if (/\bDB\s*:\s*D1Database/.test(workerTypes)) throw new Error('Generated Worker types must not expose a DB binding');
if (!repository.includes('PostgreSQL persistence authority is required')) throw new Error('Repository must fail closed on non-PostgreSQL authority');
if (!worker.includes('if (isDataRequest) authorityMode(env);')) throw new Error('Worker data boundary must fail closed before routing requests');
console.log(JSON.stringify({ ok: true, authority: 'postgres', d1Binding: false, hyperdrive: true }));
