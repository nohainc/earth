import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('economic balance report is a read-only, database-backed development command', () => {
  const script = fs.readFileSync(path.resolve('scripts/economy-report.mjs'), 'utf8');
  const packageJson = JSON.parse(fs.readFileSync(path.resolve('package.json'), 'utf8'));
  assert.equal(packageJson.scripts['economy:report'], 'node scripts/economy-report.mjs');
  for (const view of ['building_economic_balance_model', 'technology_economic_balance_model', 'economic_recipe_cycles', 'economic_resource_flow_coverage', 'tax_governance_rules']) {
    assert.match(script, new RegExp(view));
  }
  assert.match(script, /ECONOMY_REPORT_ALLOW_ERRORS/);
  assert.doesNotMatch(script, /INSERT|UPDATE|DELETE|ALTER|DROP|TRUNCATE/);
});
