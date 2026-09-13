import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/001_baseline.sql', 'utf8');
const runtime = fs.readFileSync('cloudflare/src/technology-postgres.ts', 'utf8');

test('Technology/IP V2 has corporation-owned research, patents, public domain and licenses', () => {
  for (const table of ['technology_patents', 'technology_public_domain', 'technology_license_contracts', 'technology_license_payments']) {
    assert.match(migration, new RegExp(`CREATE TABLE(?: IF NOT EXISTS)? ${table}`));
  }
  for (const fn of ['earth_technology_is_patentable', 'earth_resolve_corporation_technology_access', 'earth_grant_completed_technology_patents', 'earth_finalize_technology_public_domain']) {
    assert.match(migration, new RegExp(`FUNCTION ${fn}`));
  }
  assert.match(runtime, /JOIN house_affiliations/);
  assert.match(runtime, /CREATE.*corporation_research_projects|corporation_research_projects/);
  assert.match(runtime, /createNotification/);
  assert.match(runtime, /createGameEvent/);
  assert.match(runtime, /toNanoMarkup/);
  assert.doesNotMatch(runtime, /\bFROM\s+memberships\b|\bJOIN\s+memberships\b/i);
});
