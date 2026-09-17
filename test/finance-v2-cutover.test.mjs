import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

test('finance compatibility reads use House and canonical V5 contract tables', () => {
  const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');
  const index = fs.readFileSync('cloudflare/src/index.ts', 'utf8');
  const marketRules = fs.readFileSync('cloudflare/src/market-rules.ts', 'utf8');
  assert.doesNotMatch(routes, /global_bank_deposits|global_bank_loans|FROM tax_rules|JOIN tax_rules/);
  assert.doesNotMatch(index, /global_bank_deposits|global_bank_loans|FROM tax_rules|JOIN tax_rules/);
  assert.doesNotMatch(marketRules, /FROM tax_rules|JOIN tax_rules/);
  assert.match(routes, /o\.id = \$1[\s\S]*viewer\.house_id/);
  assert.match(routes, /FROM bank_deposits/);
  assert.match(routes, /getTaxStatement\(repository, viewer\.id\)/);
  assert.match(routes, /FROM tax_obligations/);
});

test('finance cutover verifier follows the current module layout', () => {
  const output = execFileSync(process.execPath, ['scripts/verify-finance-v2-cutover.mjs'], { encoding: 'utf8' });
  const result = JSON.parse(output);
  assert.equal(result.ready, true);
  assert.ok(result.scanned.includes('finance-routes.ts'));
  assert.ok(result.scanned.includes('financial-postgres.ts'));
  assert.ok(result.skippedObsoleteCandidates.includes('finance-postgres.ts'));
  assert.ok(result.skippedObsoleteCandidates.includes('civic-dividend-engine.ts'));
});
