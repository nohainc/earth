import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/330_public_service_projects.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const institutionsEngine = fs.readFileSync('cloudflare/src/engines/institutions-engine.ts', 'utf8');

test('public service budgets fund providers instead of creating capacity directly', () => {
  assert.match(migration, /CREATE TABLE public_service_projects/);
  assert.match(migration, /provider_building_id/);
  assert.match(migration, /budget_line_id/);
  assert.match(migration, /building_catalog/);
  assert.match(migration, /PUBLIC_CONTRACT/);
  assert.match(migration, /earth_create_public_service_project/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS public_service_projects/);
  assert.match(schema, /earth_create_public_service_project/);
  assert.doesNotMatch(institutionsEngine, /UPDATE cities\s+SET\s+(housing_capacity|energy_capacity|connectivity_capacity|health_capacity)/i);
});
