import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('finance compatibility reads use House and V2 contract tables', () => {
  const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');
  const index = fs.readFileSync('cloudflare/src/index.ts', 'utf8');
  const marketRules = fs.readFileSync('cloudflare/src/market-rules.ts', 'utf8');
  assert.doesNotMatch(routes, /global_bank_deposits|global_bank_loans|FROM tax_rules|JOIN tax_rules/);
  assert.doesNotMatch(index, /global_bank_deposits|global_bank_loans|FROM tax_rules|JOIN tax_rules/);
  assert.doesNotMatch(marketRules, /FROM tax_rules|JOIN tax_rules/);
  assert.match(routes, /o\.id = \$1[\s\S]*viewer\.house_id/);
  assert.match(routes, /FROM bank_deposits/);
  assert.match(routes, /FROM tax_rule_versions/);
  assert.match(routes, /FROM tax_obligations/);
});
