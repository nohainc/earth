import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Technology and IP V2 final acceptance contract is present', () => {
  const schema = read('db/schema.sql');
  const manifest = JSON.parse(read('db/schema-manifest.json'));
  const source = [
    read('cloudflare/src/technology-postgres.ts'),
    read('cloudflare/src/building-settlement-v2.ts'),
    read('cloudflare/src/real-estate-postgres.ts'),
    read('cloudflare/src/scheduler-postgres.ts'),
  ].join('\n');
  const migrations = [
    read('db/migrations/155_economy_v2_posting_primitives.sql'),
    read('db/migrations/255_technology_catalog.sql'),
    read('db/migrations/258_corporation_research_projects.sql'),
    read('db/migrations/262_research_economy_funding.sql'),
    read('db/migrations/264_corporation_technology_access.sql'),
    read('db/migrations/267_corporation_technology_modifier_cache.sql'),
    read('db/migrations/270_selective_technology_patents.sql'),
    read('db/migrations/273_technology_public_domain.sql'),
    read('db/migrations/274_corporation_ip_license_contracts.sql'),
    read('db/migrations/278_prepay_ip_license_access.sql'),
    read('db/migrations/282_transfer_dissolved_corporate_patents.sql'),
    read('db/migrations/283_canonical_technology_access_resolver.sql'),
    read('db/migrations/286_technology_definition_snapshots.sql'),
    read('db/migrations/289_research_scheduler_v2.sql'),
    read('db/migrations/291_ip_rd_integrity_report.sql'),
    read('db/migrations/292_deterministic_patent_race_resolution.sql'),
  ].join('\n');

  for (const table of [
    'technology_catalog', 'corporation_research_projects',
    'corporation_technology_access', 'corporation_technology_modifier_cache',
    'technology_patents', 'technology_license_contracts',
  ]) assert.ok(manifest.requiredTables[table], `${table} must be canonical`);
  for (const contract of [
    'earth_post_transaction', 'earth_resolve_corporation_technology_access',
    'earth_rebuild_corporation_technology_modifier_cache',
    'earth_settle_research_and_progress_v2', 'earth_grant_completed_technology_patents',
    'earth_finalize_technology_public_domain', 'earth_settle_technology_license_fees',
    'earth_transfer_dissolved_corporation_ip',
  ]) assert.match(migrations, new RegExp(contract));

  assert.match(migrations, /patentable BOOLEAN/);
  assert.match(migrations, /definition_snapshot JSONB/);
  assert.match(migrations, /effective_from_game_day/);
  assert.match(migrations, /paid_through_game_day/);
  assert.match(migrations, /research_capacity/);
  assert.match(migrations, /DISTINCT ON \(p\.target_id\)/);
  assert.match(migrations, /ORDER BY p\.target_id, p\.corporation_economic_id, p\.id/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /corporation_technology_modifier_cache/);
  assert.match(source, /earth_building_corporation_economic_id/);
  assert.match(source, /earth_settle_research_and_progress_v2/);

  for (const legacyPath of [
    'human_technology_adoptions', 'human_technology_subscriptions',
    'corporation_technology_shares', 'corporation_technology_projects',
    'corporation_building_research_projects', 'technology_licenses',
    'building_patent_licenses',
  ]) assert.doesNotMatch(schema, new RegExp(`CREATE TABLE IF NOT EXISTS ${legacyPath}`));
});
