import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

const sourceDirectory = new URL('../cloudflare/src/', import.meta.url);
const names = (await readdir(sourceDirectory.pathname)).filter((name) => name.endsWith('-postgres.ts'));
const failures = [];
const audited = [];

for (const name of names) {
  const source = await readFile(join(sourceDirectory.pathname, name), 'utf8');
  if (name === 'read-postgres.ts' || name === 'world-postgres.ts') continue;
  if (/\bD1Database\b|\benv\.DB\b|d1_databases/.test(source)) failures.push(`${name}: legacy D1 access is present`);

  const mutationFunctions = [...source.matchAll(/export async function\s+(\w+)\s*\(/g)]
    .map((match) => match[1])
    .filter((functionName) => !/^list|^get|^read|^ownershipRegistry$|^cityQualification$|^corporationQualification$|^transferCredits$/.test(functionName));
  if (!mutationFunctions.length) continue;

  const hasTransaction = /(?:repository|repo|tx)\.transaction\(/.test(source);
  const hasExplicitBoundary = source.includes('@mutation-boundary caller-owned-transaction') || source.includes('@mutation-boundary atomic-sql');
  const hasReplayBoundary = source.includes('correlationId') || source.includes('correlation_id') || source.includes('@mutation-boundary deterministic-settlement') || source.includes('@mutation-boundary read-only') || name === 'scheduler-postgres.ts' || name === 'roles-postgres.ts' || name === 'auth-postgres.ts' || name === 'outbox-postgres.ts';
  if (!hasTransaction && !hasExplicitBoundary && name !== 'financial-postgres.ts') failures.push(`${name}: mutation adapter has no explicit transaction boundary`);
  if (!hasReplayBoundary) failures.push(`${name}: mutation adapter has no visible idempotency/correlation boundary`);
  audited.push({ file: name, mutationFunctions, transaction: hasTransaction || hasExplicitBoundary || name === 'financial-postgres.ts', replayBoundary: hasReplayBoundary });
}

const indexSource = await readFile(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');
if (/\benv\.DB\b|D1Database|d1_databases/.test(indexSource)) failures.push('index.ts: legacy D1 access is present');
if (!indexSource.includes('authorityMode(env)')) failures.push('index.ts: PostgreSQL authority guard is missing');
if (!indexSource.includes("code: 'SERVICE_UNAVAILABLE'") && !indexSource.includes("503: 'SERVICE_UNAVAILABLE'")) failures.push('index.ts: safe uncaught-error envelope is missing');

const result = { ok: failures.length === 0, auditedAdapters: audited.length, failures, adapters: audited };
console.log(JSON.stringify(result, null, 2));
if (failures.length) process.exitCode = 1;
