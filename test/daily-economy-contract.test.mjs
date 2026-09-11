import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('the constitutional economy contract makes the game day fundamental', () => {
  const constitution = read('docs/CONSTITUTION.md');
  const spec = read('docs/GAME_ECONOMY_SPEC.md');
  assert.match(constitution, /CONST-TIME-002 — Daily economic period/);
  assert.match(constitution, /fundamental economic accounting period/);
  assert.match(spec, /## Daily Economy Contract/);
  assert.match(spec, /Fiscal months, quarters, and years are projections over daily results/);
  assert.match(spec, /monthlyIncome \/ days/);
});

test('authoritative runtime and canonical schema do not use ambiguous long-period economics', () => {
  const roots = ['cloudflare/src', 'db/schema.sql'];
  const files = roots.flatMap((root) => {
    const absolute = path.resolve(root);
    if (fs.statSync(absolute).isFile()) return [absolute];
    return fs.readdirSync(absolute, { recursive: true })
      .filter((entry) => typeof entry === 'string' && entry.endsWith('.ts'))
      .map((entry) => path.join(absolute, entry));
  });
  const forbidden = /\b(?:monthly_income|monthly_cost|annual_income|annual_cost|per_month|month_income|monthlyIncome|monthlyCost|annualIncome|annualCost)\b/i;
  for (const file of files) {
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), forbidden, `${file} contains a gameplay-period field`);
  }
});
