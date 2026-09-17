#!/usr/bin/env node
/**
 * V5-16 rehearsal coordinator.
 *
 * The command is deliberately fail-closed: artifact-only mode can validate
 * code and contracts, but a successful rehearsal requires DATABASE_URL and
 * the PostgreSQL-backed integrity/readiness checks.
 */
import { createHmac, createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const artifactOnly = process.argv.includes('--artifact-only');
const fullCertification = process.argv.includes('--full-certification');
const results = [];

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, env: process.env, stdio: 'inherit' });
    child.once('error', reject);
    child.once('exit', (code, signal) => resolve({ code: code ?? 1, signal }));
  });
}

async function step(name, command, args) {
  const started = Date.now();
  const result = await run(command, args);
  const passed = result.code === 0;
  results.push({ name, status: passed ? 'passed' : 'failed', seconds: ((Date.now() - started) / 1000).toFixed(1) });
  if (!passed) throw new Error(`${name} failed with exit code ${result.code}`);
}

async function main() {
  if (!artifactOnly && !process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL is required for a V5 cutover rehearsal; use --artifact-only only for code/contract checks');
  }

  await step('Migration order', 'npm', ['run', 'db:verify:migrations']);
  await step('Schema contract', 'npm', ['run', 'db:verify:schema-contract']);
  await step('Mutation boundaries', 'npm', ['run', 'audit:mutation-boundaries']);
  await step('V5/API contracts', 'node', ['--experimental-strip-types', '--test',
    'test/v5-progressive-capacity.test.mjs',
    'test/api-registry.test.mjs',
    'test/api-route-canonicalization.test.mjs',
    'test/flutter-api-contract-generated.test.mjs']);

  if (!artifactOnly) {
    await step('PostgreSQL surface', 'npm', ['run', 'db:verify:surface']);
    await step('PostgreSQL integrity', 'npm', ['run', 'db:verify:integrity']);
    await step('PostgreSQL invariants', 'npm', ['run', 'db:verify:invariants']);
    await step('V5 readiness gate', 'npm', ['run', 'db:verify:readiness']);
    if (fullCertification) await step('Full certification', 'npm', ['run', 'test:certification']);
  }

  const report = {
    rehearsal: 'V5-16',
    mode: artifactOnly ? 'artifact-only' : 'postgres-backed',
    status: artifactOnly ? 'artifact_checks_passed_database_rehearsal_pending' : 'passed',
    results,
    generatedAt: new Date().toISOString(),
  };
  const canonical = JSON.stringify(report);
  report.sha256 = createHash('sha256').update(canonical).digest('hex');
  if (process.env.V5_REHEARSAL_SIGNING_KEY) {
    report.signature = createHmac('sha256', process.env.V5_REHEARSAL_SIGNING_KEY).update(canonical).digest('hex');
  }
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(`V5 cutover rehearsal blocked: ${error.message}`);
  console.error(JSON.stringify({ rehearsal: 'V5-16', status: 'blocked', results }, null, 2));
  process.exitCode = 1;
});
