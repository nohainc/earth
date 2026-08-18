import { execSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { verifyDeploymentConfig } from './verify-deployment-config.mjs';

export function runPreflightChecks(options = { dryRun: true }) {
  const report = {
    timestamp: new Date().toISOString(),
    gitCommit: 'unknown',
    flutterAssetVersion: '2026-08',
    migrationVersion: 17,
    status: 'pending',
    checks: {},
    errors: [],
  };

  try {
    report.gitCommit = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {}

  // 1. Verify deployment configuration and detect route/domain conflicts
  try {
    const configReport = verifyDeploymentConfig();
    if (configReport.status === 'VALID') {
      report.checks.deploymentConfig = 'PASSED';
    } else {
      report.checks.deploymentConfig = 'FAILED';
      for (const conflict of configReport.conflicts) {
        report.errors.push(`Deployment route conflict [${conflict.type}]: ${conflict.message}`);
      }
      for (const err of configReport.errors) {
        report.errors.push(`Deployment config error: ${err}`);
      }
    }
  } catch (err) {
    report.checks.deploymentConfig = 'FAILED';
    report.errors.push(`Deployment config verification failed: ${err.message}`);
  }

  // 2. Verify schema manifest
  try {
    if (process.env.DATABASE_URL) {
      execSync('node scripts/verify-schema-manifest.mjs', { stdio: 'pipe' });
    } else {
      const manifest = JSON.parse(readFileSync(resolve('db/schema-manifest.json'), 'utf8'));
      if (!manifest.migrationVersion || !manifest.requiredTables) throw new Error('Invalid manifest JSON');
    }
    report.checks.schemaManifest = 'PASSED';
  } catch (err) {
    report.checks.schemaManifest = 'FAILED';
    report.errors.push(`Schema manifest check failed: ${err.message}`);
  }

  // 3. Verify Flutter web build assets exist
  const appHtmlPath = resolve('flutter_client/build/web/app.html');
  if (existsSync(appHtmlPath)) {
    report.checks.flutterAssets = 'PASSED';
  } else {
    report.checks.flutterAssets = 'FAILED';
    report.errors.push('Flutter web assets missing. Run `npm run flutter:prepare` first.');
  }

  // 4. Verify Wrangler dry-run deployment
  try {
    execSync('npx wrangler deploy --dry-run --config wrangler.api.jsonc', { stdio: 'pipe' });
    report.checks.wranglerDryRun = 'PASSED';
  } catch (err) {
    report.checks.wranglerDryRun = 'FAILED';
    report.errors.push(`Wrangler dry-run failed: ${err.message}`);
  }

  report.status = report.errors.length === 0 ? 'PROMOTION_READY' : 'BLOCKED';
  return report;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*[/\\]/, ''))) {
  const result = runPreflightChecks();
  console.log(JSON.stringify(result, null, 2));
  if (result.status !== 'PROMOTION_READY') {
    process.exit(1);
  }
}
