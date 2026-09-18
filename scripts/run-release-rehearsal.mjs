#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const flutterDir = join(projectRoot, 'flutter_client');
const skipDatabase = process.argv.includes('--skip-database');
const results = [];

function run(command, args, cwd = projectRoot) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, env: process.env, stdio: 'inherit' });
    child.once('error', reject);
    child.once('exit', (code, signal) => resolve({ code: code ?? 1, signal }));
  });
}

async function step(name, command, args, options = {}) {
  const started = Date.now();
  console.log(`\n[release rehearsal] ${name}`);
  const result = await run(command, args, options.cwd ?? projectRoot);
  const passed = result.code === 0;
  results.push({ name, command: [command, ...args].join(' '), status: passed ? 'passed' : 'failed', seconds: ((Date.now() - started) / 1000).toFixed(1) });
  if (!passed) throw new Error(`${name} failed with exit code ${result.code}${result.signal ? ` (${result.signal})` : ''}`);
}

async function main() {
  console.log('EARTH Phase 7 release rehearsal (fail-closed)');
  if (!skipDatabase && !process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL is required for a release rehearsal; use --skip-database only for artifact-only checks');
  }

  if (!skipDatabase) {
    await step('Migration order and checksum policy', 'npm', ['run', 'db:verify:migrations']);
    await step('Database schema manifest', 'npm', ['run', 'db:verify:manifest']);
    await step('Database canonical schema', 'npm', ['run', 'db:verify:canonical']);
    await step('Database invariants', 'npm', ['run', 'db:verify:invariants']);
  }

  await step('Schema contract synchronization', 'npm', ['run', 'db:verify:schema-contract']);
  await step('Deployment routes and coverage', 'npm', ['run', 'deploy:verify:config']);
  await step('Dependency security audit', 'npm', ['run', 'security:audit']);
  await step('Mutation boundary audit', 'npm', ['run', 'audit:mutation-boundaries']);
  await step('Flutter static analysis', 'flutter', ['analyze'], { cwd: flutterDir });
  await step('Flutter web release build', 'flutter', ['build', 'web', '--release'], { cwd: flutterDir });
  if (!existsSync(join(flutterDir, 'build', 'web', 'app.html'))) throw new Error('Flutter release build did not produce app.html');
  await step('Full Flutter test suite', 'flutter', ['test'], { cwd: flutterDir });
  await step('Maintained V4 page contracts', 'npm', ['run', 'test:pages']);
  await step('Backend certification suite', 'npm', ['run', 'test:certification']);
  await step('Local deployment endpoints and asset canary', 'node', ['--test', 'test/deployment-verification.test.mjs', 'test/production-assets.test.mjs']);

  console.log('\nRelease rehearsal summary');
  console.table(results);
  console.log(`Release rehearsal passed: ${results.length} gates`);
}

main().catch((error) => {
  console.error(`\nRelease rehearsal blocked: ${error.message}`);
  console.table(results);
  process.exitCode = 1;
});
