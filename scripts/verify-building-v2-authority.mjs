import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const v2 = read('cloudflare/src/building-settlement-v2.ts');
const legacy = read('cloudflare/src/building-settlement-engine.ts');
const profiles = read('cloudflare/src/daily-settlement-profiles.ts');
const phases = read('cloudflare/src/daily-settlement-phases.ts');

const findings = [];
if (/UPDATE economic_accounts|UPDATE account_balances|UPDATE resource_balances/.test(v2)) {
  findings.push('V2 building settlement directly mutates a balance table');
}
if (!v2.includes('settlement_effects') || !v2.includes('building_settlement_journals')) {
  findings.push('V2 building settlement lacks effect/journal output');
}
if (legacy.includes('account_balances') || legacy.includes('resource_balances') || legacy.includes('transferCredits')) {
  findings.push('legacy building settlement still contains balance mutation paths');
}
if (!profiles.includes('earth_rebuild_dirty_profiles') || !profiles.includes('earth_catchup_owner_settlement')) {
  findings.push('profile settlement boundary could not be located');
}
if (!phases.includes("id: 'building_settlement'")) {
  findings.push('building settlement is not present in the canonical phase registry');
}

console.log(JSON.stringify({
  status: findings.length === 0 ? 'pass' : 'audit_findings',
  v2Path: 'cloudflare/src/building-settlement-v2.ts',
  legacyPath: 'cloudflare/src/building-settlement-engine.ts',
  findings,
}, null, 2));

// Findings are expected until the later replacement plans. Structural
// authority violations in the V2 path remain hard failures.
if (/UPDATE economic_accounts|UPDATE account_balances|UPDATE resource_balances/.test(v2)) process.exitCode = 1;
