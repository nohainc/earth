#!/usr/bin/env node
import 'dotenv/config';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const flutterDir = join(projectRoot, 'flutter_client');

async function runStep(name, command, args, cwd = projectRoot) {
  console.log(`\n============================================================`);
  console.log(`[TEST PIPELINE] Step: ${name}`);
  console.log(`Command: ${command} ${args.join(' ')} (in ${cwd})`);
  console.log(`============================================================\n`);

  const code = await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: process.env,
      stdio: 'inherit',
    });
    child.once('error', reject);
    child.once('exit', (exitCode) => resolve(exitCode ?? 1));
  });

  if (code !== 0) {
    console.error(`\n❌ [TEST PIPELINE] Step "${name}" failed with exit code ${code}.`);
    process.exit(code);
  }
  console.log(`\n✅ [TEST PIPELINE] Step "${name}" passed successfully.`);
}

async function main() {
  const startTime = Date.now();
  console.log(`🚀 Starting Complete Earth Test Suite Pipeline\n`);

  // Step 1: Flutter Static Analysis
  await runStep('1. Flutter Static Analysis', 'flutter', ['analyze'], flutterDir);

  // Step 2: Flutter Unit, Widget & Golden Test Suite
  await runStep('2. Flutter Test Suite', 'flutter', ['test'], flutterDir);

  // Step 3: Flutter Web Build Verification
  await runStep('3. Flutter Web Release Build', 'flutter', ['build', 'web', '--release'], flutterDir);

  // Step 4: Backend & Database Integrity Suite
  await runStep('4. Backend & Database Tests', 'npm', ['test'], projectRoot);

  // Step 5: Playwright Authenticated Browser Journeys
  await runStep('5. Playwright UI Journeys', 'node', ['scripts/run-ui-tests.mjs'], projectRoot);

  const durationSec = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log(`\n============================================================`);
  console.log(`🎉 ALL TEST TIERS COMPLETED SUCCESSFULLY in ${durationSec}s!`);
  console.log(`============================================================\n`);
}

main().catch((err) => {
  console.error(`\n❌ Pipeline crashed:`, err);
  process.exit(1);
});
