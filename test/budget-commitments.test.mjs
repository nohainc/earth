import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('budget commitments reserve and release line authority atomically', () => {
  const migration = read('db/migrations/320_budget_commitments.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /CREATE TABLE institution_budget_commitments/);
  assert.match(migration, /budget_line_id BIGINT NOT NULL REFERENCES institution_budget_lines\(id\)/);
  assert.match(migration, /original_units BIGINT NOT NULL/);
  assert.match(migration, /remaining_units BIGINT NOT NULL/);
  assert.match(migration, /AFTER INSERT/);
  assert.match(migration, /FOR UPDATE/);
  assert.match(migration, /original_units > available_units/);
  assert.match(migration, /committed_units = committed_units \+ NEW\.original_units/);
  assert.match(migration, /earth_pay_budget_commitment/);
  assert.match(migration, /committed_units = committed_units - p_payment_units/);
  assert.match(migration, /spent_units = spent_units \+ p_payment_units/);
  assert.match(migration, /earth_cancel_budget_commitment/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_budget_commitments/);
});

test('budget commitments are part of the canonical schema manifest', () => {
  const manifest = JSON.parse(read('db/schema-manifest.json'));
  assert.deepEqual(manifest.requiredTables.institution_budget_commitments.slice(0, 9), [
    'id', 'institution_id', 'budget_line_id', 'commitment_type', 'source_type',
    'source_id', 'original_units', 'remaining_units', 'status',
  ]);
});
