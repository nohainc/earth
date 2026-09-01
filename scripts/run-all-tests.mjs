#!/usr/bin/env node
import 'dotenv/config';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const flutterDir = join(projectRoot, 'flutter_client');

const stepResults = [];

async function runStep(name, command, args, cwd = projectRoot) {
  console.log(`\n============================================================`);
  console.log(`[TEST PIPELINE] Step: ${name}`);
  console.log(`Command: ${command} ${args.join(' ')} (in ${cwd})`);
  console.log(`============================================================\n`);

  const stepStart = Date.now();
  let status = 'PASSED';
  let exitCode = 0;

  try {
    exitCode = await new Promise((resolve, reject) => {
      const child = spawn(command, args, {
        cwd,
        env: process.env,
        stdio: 'inherit',
      });
      child.once('error', reject);
      child.once('exit', (code) => resolve(code ?? 1));
    });
  } catch (err) {
    status = 'ERROR';
    exitCode = 1;
  }

  const durationSec = ((Date.now() - stepStart) / 1000).toFixed(1);

  if (exitCode !== 0) {
    status = 'FAILED';
  }

  stepResults.push({
    step: name,
    command: `${command} ${args.join(' ')}`,
    duration: `${durationSec}s`,
    status,
  });

  if (exitCode !== 0) {
    console.error(`\n❌ [TEST PIPELINE] Step "${name}" failed with exit code ${exitCode}.`);
    printSummary(false);
    process.exit(exitCode);
  }

  console.log(`\n✅ [TEST PIPELINE] Step "${name}" passed in ${durationSec}s.`);
}

function printSummary(allPassed = true) {
  console.log(`\n\n============================================================`);
  console.log(`📊 EARTH TEST PIPELINE SUMMARY REPORT`);
  console.log(`============================================================`);
  console.table(stepResults);

  const totalTime = stepResults
    .reduce((sum, item) => sum + parseFloat(item.duration), 0)
    .toFixed(1);

  if (allPassed) {
    console.log(`🎉 ALL ${stepResults.length} TEST TIERS COMPLETED SUCCESSFULLY in ${totalTime}s!`);
  } else {
    console.log(`⚠️ PIPELINE FAILED after ${totalTime}s.`);
  }
  console.log(`============================================================\n`);
}

async function main() {
  console.log(`🚀 Starting Complete Earth Test Suite Pipeline\n`);

  // Step 1: Flutter Static Analysis
  await runStep('1. Flutter Static Analysis', 'flutter', ['analyze'], flutterDir);

  // Step 2: Flutter Unit, Widget & Golden Test Suite
  await runStep('2. Flutter Test Suite (84+ files, 245+ tests, goldens)', 'flutter', ['test'], flutterDir);

  // Step 3: Flutter Web Build Verification
  await runStep('3. Flutter Web Release Build', 'flutter', ['build', 'web', '--release'], flutterDir);

  // Step 4: Backend & Database Integrity Suite
  await runStep('4. Backend & Database Integrity Suite', 'npm', ['test'], projectRoot);

  // Step 5: Playwright Authenticated Browser Journeys
  await runStep('5. Playwright E2E UI Journeys (61 journeys)', 'node', ['scripts/run-ui-tests.mjs'], projectRoot);

  printSummary(true);
}

main().catch((err) => {
  console.error(`\n❌ Pipeline crashed:`, err);
  process.exit(1);
});
