import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('canonical schema and manifest exclude removed building economy fields', () => {
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));

  assert.doesNotMatch(schema, /\boutput_credits\b/);
  assert.doesNotMatch(schema, /\bdecay_multiplier\b/);
  assert.doesNotMatch(schema, /\bauto_repair_enabled\b/);
  assert.doesNotMatch(schema, /\brepair_target_condition\b/);
  assert.doesNotMatch(schema, /\bcondition_curve_version\b/);

  const buildingTables = ['buildings', 'building_catalog', 'building_economic_rule_versions',
    'building_settlement_journals', 'building_settlement_plans'];
  for (const table of buildingTables) {
    const fields = manifest.requiredTables[table] ?? [];
    for (const field of ['output_credits', 'auto_repair_enabled', 'repair_target_condition',
      'condition_curve_version', 'wear_points', 'repair_points']) {
      assert.ok(!fields.includes(field), `${table}.${field} must not be in the canonical manifest`);
    }
  }
});
