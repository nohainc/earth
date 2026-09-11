import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/331_institution_account_provisioning.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const source = fs.readFileSync('cloudflare/src/institutions-postgres.ts', 'utf8');

test('new institutions provision Economy V2 treasury topology', () => {
  assert.match(migration, /VALUES \(3\), \(4\), \(5\)/);
  assert.match(migration, /earth_provision_institution_accounts/);
  assert.match(migration, /account_type = 3/);
  assert.match(schema, /earth_provision_institution_accounts/);
  assert.match(source, /earth_provision_institution_accounts/);
  assert.doesNotMatch(source.slice(source.indexOf('export async function createCity'), source.indexOf('export async function cityQualification')), /INSERT INTO account_balances/);
  assert.doesNotMatch(source.slice(source.indexOf('export async function createCorporationWithCapital'), source.indexOf('export async function corporationQualification')), /INSERT INTO account_balances/);
});
