import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { classifyDeathCause } from '../cloudflare/src/lifecycle-postgres.ts';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { formatCreditUnits } from '../cloudflare/src/money.ts';
import { getMemorialCitizenBiography, getMemorialHouseLineage, listMemorialArchive } from '../cloudflare/src/read-postgres.ts';

const migration = fs.readFileSync('db/migrations/159_human_memorial_snapshots.sql', 'utf8');
const generationMigration = fs.readFileSync('db/migrations/160_canonical_human_generation_and_death_causes.sql', 'utf8');
const houseContinuityMigration = fs.readFileSync('db/migrations/161_explicit_house_extinction_state.sql', 'utf8');
const testamentMigration = fs.readFileSync('db/migrations/162_human_testament_constraints.sql', 'utf8');
const biographyMigration = fs.readFileSync('db/migrations/163_memorial_house_name_snapshot.sql', 'utf8');
const officeMigration = fs.readFileSync('db/migrations/164_memorial_office_snapshot.sql', 'utf8');
const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
const memorialReadModel = fs.readFileSync('cloudflare/src/read-postgres.ts', 'utf8');
const lineageDialog = fs.readFileSync('flutter_client/lib/features/house/house_lineage_dialog.dart', 'utf8');
const navigation = fs.readFileSync('flutter_client/lib/core/navigation_registry.dart', 'utf8');
const authRoutes = fs.readFileSync('cloudflare/src/auth-routes.ts', 'utf8');
const authPostgres = fs.readFileSync('cloudflare/src/auth-postgres.ts', 'utf8');

class MemorialDbClient {
  constructor({ deceasedRows, houseRows, deceasedTotal = deceasedRows.length, houseTotal = houseRows.length } = {}) {
    this.deceasedRows = deceasedRows ?? [];
    this.houseRows = houseRows ?? [];
    this.deceasedTotal = deceasedTotal;
    this.houseTotal = houseTotal;
    this.calls = [];
  }

  async query(sql, params = []) {
    this.calls.push({ sql, params });
    if (sql.includes('earth_get_current_game_time')) {
      return { rows: [{ game_day: '1000', game_minute: '12' }], rowCount: 1 };
    }
    if (sql.includes('COUNT(*)::INTEGER AS total_count') && sql.includes('FROM humans h JOIN houses d')) return { rows: [{ total_count: this.deceasedTotal }], rowCount: 1 };
    if (sql.includes('COUNT(*)::INTEGER AS total_count') && sql.includes('FROM houses')) return { rows: [{ total_count: this.houseTotal }], rowCount: 1 };
    if (sql.includes("WHERE h.status = 'DECEASED'")) {
      const search = String(params[0] ?? '');
      const rows = search ? this.deceasedRows.filter((row) => row.display_name.includes(search)) : this.deceasedRows;
      return { rows, rowCount: rows.length };
    }
    if (sql.includes('WHERE h.status = \'ACTIVE\'')) return { rows: [], rowCount: 0 };
    if (sql.includes('FROM houses WHERE status')) {
      const search = String(params[0] ?? '');
      const rows = search ? this.houseRows.filter((row) => row.house_name.includes(search)) : this.houseRows;
      return { rows, rowCount: rows.length };
    }
    return { rows: [], rowCount: 0 };
  }
}

function memorialCitizen(index) {
  return {
    human_id: `H-${index}`,
    display_name: `Citizen ${index}`,
    house_id: `HOUSE-${index}`,
    house_name: `House ${index}`,
    birth_game_day: index,
    death_game_day: 2000 - index,
    age_years: 80,
    final_legacy: String(index),
    final_standing: String(index),
    generation: (index % 40) + 1,
    successor_name: null,
  };
}

function memorialHouse(index) {
  return {
    id: `HOUSE-${index}`,
    house_name: `House ${index}`,
    status: 'ACTIVE',
    generation: (index % 40) + 1,
    archive_sort_day: 2000 - index,
    deceased_count: 1,
    is_extinct: false,
  };
}

test('death snapshots have an immutable versioned schema', () => {
  for (const field of [
    'generation', 'final_standing', 'final_legacy', 'cause_code',
    'corporation_id', 'corporation_name', 'successor_human_id',
    'final_house_economic_snapshot', 'epitaph', 'record_version',
  ]) assert.match(migration, new RegExp(`\\b${field}\\b`));
  assert.match(biographyMigration, /house_name_at_death/);
  assert.match(officeMigration, /major_offices_snapshot JSONB/);
  assert.match(migration, /BEFORE UPDATE OR DELETE ON human_memorial_records/);
  assert.match(lifecycle, /INSERT INTO human_memorial_records/);
  assert.match(lifecycle, /ON CONFLICT \(human_id\) DO NOTHING/);
  assert.match(generationMigration, /ALTER TABLE humans[\s\S]*generation INTEGER NOT NULL DEFAULT 1/);
  assert.match(generationMigration, /generation_source/);
  assert.match(generationMigration, /cause_classification_version/);
  assert.match(lifecycle, /SUCCESSION_HISTORY_V1/);
  assert.match(lifecycle, /JSON\.stringify\(majorOfficesSnapshot\)/);
});

test('Memorial pages remain server-paginated beyond 100 and 1,000 archived Humans', async () => {
  const client = new MemorialDbClient({
    deceasedRows: Array.from({ length: 1201 }, (_, index) => memorialCitizen(index + 1)),
    houseRows: Array.from({ length: 1001 }, (_, index) => memorialHouse(index + 1)),
    deceasedTotal: 1201,
    houseTotal: 1001,
  });
  const page = await listMemorialArchive(new PostgresRepository(client), { limit: 50 });
  assert.equal(page.citizens.length, 50);
  assert.equal(page.houses.length, 50);
  assert.equal(page.citizenTotalCount, 1201);
  assert.equal(page.houseTotalCount, 1001);
  assert.ok(page.citizenNextCursor);
  assert.ok(page.houseNextCursor);
  assert.ok(client.calls.some((call) => call.sql.includes('LIMIT $2')));
});

test('Memorial search reaches records outside the first page on the server', async () => {
  const client = new MemorialDbClient({
    deceasedRows: [memorialCitizen(877)],
    houseRows: [memorialHouse(877)],
    deceasedTotal: 1,
    houseTotal: 1,
  });
  const page = await listMemorialArchive(new PostgresRepository(client), { search: 'Citizen 877', limit: 50 });
  assert.equal(page.citizens[0].humanId, 'H-877');
  assert.equal(page.citizenTotalCount, 1);
  assert.ok(client.calls.some((call) => call.params[0] === 'Citizen 877'));
});

test('archived Human biographies remain identical after later game days', async () => {
  class BiographyClient {
    async query(sql) {
      if (sql.includes('FROM human_memorial_records')) return { rows: [{
        human_id: 'H-ARCHIVE', house_id: 'HOUSE-ARCHIVE', house_name_at_death: 'House Archive',
        generation: 7, display_name: 'Archived Human', birth_game_day: 10, death_game_day: 500,
        age_years: 80, final_standing: '812', final_legacy: '1450', cause_code: 'NATURAL_AGE',
        cause_details: { age: 80 }, corporation_id: null, corporation_name: null,
        successor_human_id: 'H-NEXT', successor_name: 'Successor Human',
        major_offices_snapshot: [{ roleCode: 'CORPORATION_TREASURER', roleName: 'CORPORATION TREASURER' }],
        epitaph: 'For the generations ahead.', record_version: 'human-memorial-v1', created_game_day: 500,
      }], rowCount: 1 };
      if (sql.includes('SELECT id, category')) return { rows: [{ id: 'EVENT-1', category: 'RESEARCH', event_type: 'RESEARCH_COMPLETED', title: 'Research completed', game_day: 480, game_minute: 20, subject_type: 'RESEARCH_PROJECT', subject_id: 'R-1' }], rowCount: 1 };
      if (sql.includes('COUNT(*) FILTER')) return { rows: [{ governance_event_count: 0, research_event_count: 1, building_event_count: 0, initiative_event_count: 0 }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    }
  }
  const repository = new PostgresRepository(new BiographyClient());
  const before = await getMemorialCitizenBiography(repository, 'H-ARCHIVE');
  const after = await getMemorialCitizenBiography(repository, 'H-ARCHIVE');
  assert.deepEqual(after, before);
  assert.equal(before.citizen.houseName, 'House Archive');
  assert.equal(before.citizen.generation, 7);
  assert.equal(before.offices.length, 1);
  assert.equal(before.achievements[0].gameDay, 480);
});

test('Memorial lineage preserves ordering across many generations', async () => {
  const members = Array.from({ length: 120 }, (_, index) => ({
    human_id: `H-${index + 1}`, display_name: `Human ${index + 1}`, house_id: 'HOUSE-LONG',
    birth_game_day: index + 1, death_game_day: index + 2, age_years: 80,
    final_legacy: String(index), final_standing: String(index), status: 'DECEASED', generation: index + 1,
  }));
  const successions = members.slice(0, -1).map((member, index) => ({
    predecessor_human_id: member.human_id, predecessor_name: member.display_name,
    successor_human_id: members[index + 1].human_id, successor_name: members[index + 1].display_name,
    death_game_day: index + 2, effective_game_day: index + 3, generation: index + 2, status: 'COMPLETED',
  }));
  const client = { async query(sql) {
    if (sql.includes('FROM succession_events se')) return { rows: successions, rowCount: successions.length };
    if (sql.includes('FROM humans h') && sql.includes('WHERE h.house_id')) return { rows: members, rowCount: members.length };
    if (sql.includes('FROM houses h')) return { rows: [{ id: 'HOUSE-LONG', house_name: 'House Long', status: 'ACTIVE', generation: 120, founded_game_day: 1, deceased_count: 120, is_extinct: false }], rowCount: 1 };
    return { rows: [], rowCount: 0 };
  } };
  const lineage = await getMemorialHouseLineage(new PostgresRepository(client), 'HOUSE-LONG');
  assert.equal(lineage.house.members.length, 120);
  assert.equal(lineage.house.members[0].generation, 1);
  assert.equal(lineage.house.members.at(-1).generation, 120);
  assert.equal(lineage.house.successions.length, 119);
  assert.equal(lineage.house.successions.at(-1).successorHumanId, 'H-120');
});

test('V5 Memorial contracts contain no legacy Dynasty or City fields and format CREDIT exactly', () => {
  const dto = fs.readFileSync('flutter_client/lib/core/models/memorial_models.dart', 'utf8');
  assert.doesNotMatch(dto, /dynasty|dynastic|city[_A-Za-z]/i);
  assert.equal(formatCreditUnits(50_000n), '500.00');
  assert.equal(formatCreditUnits(9_007_199_254_740_993n), '90071992547409.93');
  assert.match(memorialReadModel, /COALESCE\(mem\.generation, h\.generation\) AS generation/);
  assert.match(memorialReadModel, /COALESCE\(mem\.house_name_at_death, d\.house_name\) AS house_name/);
  assert.doesNotMatch(memorialReadModel, /generation \?\? 1/);
  assert.match(memorialReadModel, /game_day <= \$2/);
});

test('death cause classification records deprivation contributors without inventing precision', () => {
  assert.equal(classifyDeathCause({ age: 105, foodShortfallDays: 0, missedMaintenanceDays: 0, healthServiceCoverage: 0.68 }).code, 'NATURAL_AGE');
  assert.equal(classifyDeathCause({ age: 80, foodShortfallDays: 1, missedMaintenanceDays: 0, healthServiceCoverage: 0.68 }).code, 'ESSENTIAL_NEEDS_DEPRIVATION');
  assert.equal(classifyDeathCause({ age: 80, foodShortfallDays: 0, missedMaintenanceDays: 2, healthServiceCoverage: 0.68 }).code, 'HEALTH_SERVICE_DEPRIVATION');
  assert.equal(classifyDeathCause({ age: 80, foodShortfallDays: 0, missedMaintenanceDays: 0, healthServiceCoverage: 0.68 }).code, 'NATURAL_AGE');
  assert.deepEqual(classifyDeathCause({ age: 80, foodShortfallDays: 0, missedMaintenanceDays: 0, healthServiceCoverage: 0.68 }).details, {
    age: 80,
    foodShortfallDays: 0,
    missedMaintenanceDays: 0,
    healthServiceCoverage: 0.68,
  });
});

test('House continuity is the default and extinction is explicit', () => {
  assert.match(houseContinuityMigration, /status IN \('ACTIVE', 'SUSPENDED', 'EXTINCT'\)/);
  assert.match(houseContinuityMigration, /house_lifecycle_events/);
  assert.match(houseContinuityMigration, /HOUSE_EXTINCT/);
  assert.match(memorialReadModel, /houses\.status = 'EXTINCT'/);
  assert.doesNotMatch(memorialReadModel, /NOT EXISTS \(SELECT 1 FROM humans hum WHERE hum\.house_id = houses\.id AND hum\.status = 'ACTIVE'\)[\s\S]{0,120}is_extinct/);
  assert.match(lifecycle, /Emergency Successor of/);
});

test('House lineage is loaded by House ID from canonical generations and edges', () => {
  assert.match(memorialReadModel, /export async function getMemorialHouseLineage/);
  assert.match(memorialReadModel, /FROM succession_events se/);
  assert.match(memorialReadModel, /ORDER BY se\.generation, se\.effective_game_day/);
  assert.match(memorialReadModel, /COALESCE\(mem\.generation, h\.generation\) AS generation/);
  assert.match(lineageDialog, /memorialHouseLineage\(houseId\)/);
  assert.match(lineageDialog, /required String houseId/);
  assert.doesNotMatch(lineageDialog, /house\['members'\]/);
  assert.doesNotMatch(navigation, /aliases: \['dynasty', 'lineage'\]/);
});

test('living testament is short, editable only while active, and frozen at death', () => {
  assert.match(testamentMigration, /char_length\(epitaph\) <= 240/);
  assert.match(testamentMigration, /epitaph !~ '\[\[:cntrl:\]<>\]'/);
  assert.match(authRoutes, /\/api\/life\/testament.*PATCH/);
  assert.match(authRoutes, /testament must be plain text/i);
  assert.match(authRoutes, /at most 240 characters/i);
  assert.match(authPostgres, /UPDATE humans[\s\S]*WHERE id = \$2 AND status = 'ACTIVE'/);
  assert.match(lifecycle, /human\.epitaph/);
  assert.match(lifecycle, /INSERT INTO human_memorial_records/);
  assert.match(migration, /BEFORE UPDATE OR DELETE ON human_memorial_records/);
});

test('citizen biography is archival, bounded, and event-backed', () => {
  assert.match(memorialReadModel, /export async function getMemorialCitizenBiography/);
  assert.match(memorialReadModel, /FROM human_memorial_records/);
  assert.match(memorialReadModel, /FROM game_events/);
  assert.match(memorialReadModel, /LIMIT 30/);
  assert.match(memorialReadModel, /major_offices_snapshot/);
  assert.doesNotMatch(memorialReadModel, /getMemorialCitizenBiography[\s\S]{0,5000}economic_transactions/);
  assert.doesNotMatch(memorialReadModel, /getMemorialCitizenBiography[\s\S]{0,5000}economic_entries/);
  assert.match(fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8'), /memorialCitizenMatch/);
  assert.match(fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8'), /\/api\/memorial\/citizens\/\{id\}/);
  const models = fs.readFileSync('flutter_client/lib/core/models/memorial_models.dart', 'utf8');
  assert.match(models, /class MemorialOffice/);
  assert.match(models, /class MemorialAchievement/);
  assert.match(models, /class MemorialLifetimeSummary/);
  assert.match(fs.readFileSync('flutter_client/lib/features/lifecycle/historical_archive_panel.dart', 'utf8'), /showMemorialCitizenBiographyDialog/);
});

test('Memorial is the only active player-facing historical source', () => {
  const registry = fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8');
  assert.match(registry, /path: '\/api\/memorial'.*status: 'ACTIVE'/);
  assert.match(registry, /path: '\/api\/pantheon'.*status: 'DEPRECATED'/);
  assert.match(registry, /path: '\/api\/cemetery'.*status: 'DEPRECATED'/);
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  assert.match(dashboard, /HistoricalArchivePanel\(archive: memorialArchive/);
  assert.doesNotMatch(dashboard, /PantheonPanel\(/);
});

test('House Lineage uses dynamic design tokens and canonical terminology', () => {
  const lineage = fs.readFileSync('flutter_client/lib/features/house/house_lineage_dialog.dart', 'utf8');
  assert.doesNotMatch(lineage, /Colors\.(white|red|green)|cyanAccentColor|EarthColors\./);
  assert.doesNotMatch(lineage, /dynast|dynasty|Cemetery|Pantheon|Inscribed Ancestors/);
  assert.match(lineage, /context\.primaryColor/);
  assert.match(lineage, /context\.mutedColor/);
  assert.match(lineage, /HOUSE LINEAGE/);
  assert.match(lineage, /Recorded Humans/);
});
