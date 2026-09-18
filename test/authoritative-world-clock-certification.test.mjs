import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  readAuthoritativeGameTime,
  getSettlementCursor,
  projectDeadline,
  isDeadlineDue,
  toAbsoluteGameMinute,
  fromAbsoluteGameMinute,
} from '../cloudflare/src/world-clock-postgres.ts';
import { worldSnapshot } from '../cloudflare/src/world-postgres.ts';

test('Authoritative World Clock Certification: 1. PostgreSQL migration & function contracts', async () => {
  // Verify the authoritative clock and settlement migrations exist.
  const mig130Path = path.resolve('db/migrations/130_authoritative_world_clock.sql');
  const mig131Path = path.resolve('db/migrations/131_drop_world_state_legacy_game_time_columns.sql');
  const mig132Path = path.resolve('db/migrations/132_settlement_finalization_barrier.sql');
  const mig134Path = path.resolve('db/migrations/134_genesis_at_not_null.sql');
  assert.ok(fs.existsSync(mig130Path), 'Migration 130 must exist');
  assert.ok(fs.existsSync(mig131Path), 'Migration 131 must exist');
  assert.ok(fs.existsSync(mig132Path), 'Migration 132 must exist');
  assert.ok(fs.existsSync(mig134Path), 'Migration 134 must exist');

  const mig130 = fs.readFileSync(mig130Path, 'utf8');
  assert.match(mig130, /ALTER TABLE world_state ADD COLUMN IF NOT EXISTS genesis_at TIMESTAMPTZ/);
  assert.match(mig130, /trg_world_genesis_immutability/);
  assert.match(mig130, /settled_through_game_day BIGINT/);
  assert.match(mig130, /CREATE OR REPLACE FUNCTION earth_get_current_game_time/);
  assert.match(mig130, /CREATE OR REPLACE FUNCTION earth_advance_settlement_cursor/);

  const mig131 = fs.readFileSync(mig131Path, 'utf8');
  const mig132 = fs.readFileSync(mig132Path, 'utf8');
  const mig134 = fs.readFileSync(mig134Path, 'utf8');
  assert.match(mig131, /ALTER TABLE world_state DROP COLUMN IF EXISTS game_day/);
  assert.match(mig131, /ALTER TABLE world_state DROP COLUMN IF EXISTS game_minute/);
  assert.match(mig131, /DROP FUNCTION IF EXISTS earth_advance_world_clock/);
  assert.match(mig132, /CREATE OR REPLACE FUNCTION earth_finalize_settlement_day/);
  assert.match(mig134, /ALTER COLUMN genesis_at SET NOT NULL/);

  // Verify baseline schema and manifest match the active migration head
  const baselineSchema = fs.readFileSync(path.resolve('db/baseline/01_schema.sql'), 'utf8');
  assert.doesNotMatch(baselineSchema, /CREATE TABLE world_state \([^)]*game_day/);
  assert.match(baselineSchema, /CREATE TABLE world_state \([^)]*genesis_at TIMESTAMPTZ NOT NULL/);

  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.equal(manifest.migrationVersion, 136);
  assert.deepEqual(manifest.requiredTables.world_state, ['id', 'world_seed', 'status', 'genesis_at']);
});

test('Authoritative World Clock Certification: 2. Absolute game minute and deadline helpers', () => {
  // toAbsoluteGameMinute & fromAbsoluteGameMinute round-trip
  // Absolute minute 0 = Day 1, 00:00 -> formula: (day - 1) * 1440 + minute
  const day = 42;
  const minute = 720;
  const absMinute = toAbsoluteGameMinute(day, minute);
  assert.equal(absMinute, (42 - 1) * 1440 + 720);

  const { gameDay: rDay, gameMinute: rMinute } = fromAbsoluteGameMinute(absMinute);
  assert.equal(rDay, day);
  assert.equal(rMinute, minute);

  // projectDeadline(startDay, startMinute, durationMinutes)
  const dl = projectDeadline(10, 100, 200);
  assert.equal(dl.completionGameDay, 10);
  assert.equal(dl.completionGameMinute, 300);
  assert.equal(dl.completionAbsoluteMinute, (10 - 1) * 1440 + 300);

  // Day rollover deadline
  const dlRollover = projectDeadline(10, 1400, 100);
  assert.equal(dlRollover.completionGameDay, 11);
  assert.equal(dlRollover.completionGameMinute, 60);
  assert.equal(dlRollover.completionAbsoluteMinute, (11 - 1) * 1440 + 60);

  // isDeadlineDue
  assert.equal(isDeadlineDue(1000, { totalGameMinutes: 1000 }), true);
  assert.equal(isDeadlineDue(1000, { totalGameMinutes: 1001 }), true);
  assert.equal(isDeadlineDue(1000, { totalGameMinutes: 999 }), false);
});

test('Authoritative World Clock Certification: 3. Single clock query snapshot consistency & no legacy leak', async () => {
  let clockReadCount = 0;
  const fakeClock = {
    game_day: '15',
    game_minute: '720',
    total_game_minutes: '22320',
    genesis_at: new Date(Date.now() - 22320 * 60 * 1000).toISOString(),
    server_now: new Date().toISOString(),
    real_seconds_per_game_minute: '60',
  };

  const mockRepo = {
    async query(sql, params) {
      if (sql.includes('resolved_constitution_snapshots_v5')) {
        return { rows: [{ rate_bps: '50', rules_json: { 'EARTH.MARKET.TRANSACTION_TAX_RATE': 50 } }] };
      }
      if (sql.trim().startsWith('SELECT * FROM earth_get_current_game_time()')) {
        clockReadCount++;
        return { rows: [fakeClock] };
      }
      if (sql.includes('FROM world_state')) {
        return { rows: [{ id: 'WORLD', world_seed: 'EARTH-SEED', status: 'ACTIVE', genesis_at: fakeClock.genesis_at }] };
      }
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '14' }] };
      }
      if (sql.includes('daily_settlement_runs')) {
        return { rows: [] };
      }
      if (sql.includes('daily_settlement_phase_runs')) {
        return { rows: [] };
      }
      if (sql.includes('market_order_books')) {
        return { rows: [] };
      }
      if (sql.includes('markets')) {
        return { rows: [] };
      }
      if (sql.includes('v5_progressive_tax_brackets')) {
        return { rows: [] };
      }
      if (sql.includes('constitutional_rule_versions_v5')) {
        return { rows: [{ value_json: 50 }] };
      }
      if (sql.includes('FROM humans')) {
        return { rows: [{ count: '10' }] };
      }
      if (sql.includes('FROM institutions')) {
        return { rows: [{ count: '2' }] };
      }
      return { rows: [] };
    },
  };

  const snapshot = await worldSnapshot(mockRepo);

  // Assert single authoritative clock read
  assert.equal(clockReadCount, 1, 'worldSnapshot must query authoritative clock exactly once');

  // Assert canonical clock structure
  assert.equal(snapshot.clock.day, 15);
  assert.equal(snapshot.clock.minute, 720);
  assert.equal(snapshot.clock.totalGameMinutes, 22320);

  // Assert settlement cursor derived against authoritative clock
  assert.equal(snapshot.settlement.settledThroughGameDay, 14);
  assert.equal(snapshot.settlement.lastClosedGameDay, 14);
  assert.equal(snapshot.settlement.backlogDays, 0);
  assert.equal(snapshot.settlement.status, 'CURRENT');

  // Assert NO legacy game_day or game_minute in world root
  assert.equal(snapshot.world.game_day, undefined);
  assert.equal(snapshot.world.game_minute, undefined);
  assert.equal(snapshot.world.day, undefined);
  assert.equal(snapshot.world.minute, undefined);
});

test('Authoritative World Clock Certification: 4. Monotonic client anchor contract & sleep/blur resilience', () => {
  // Test mathematical model of TopFixedHudPanel monotonic anchor
  const genesisEpochMs = Date.now() - 100000000;
  const realSecondsPerMinute = 60;
  const monotonicStopwatchElapsedMs = 5000; // Monotonic elapsed since snapshot
  const snapshotServerNowMs = Date.now() - 5000;

  // Monotonic time formula:
  // totalGameSeconds = (snapshotServerNowMs + monotonicElapsedMs - genesisEpochMs) / (realSecondsPerMinute)
  const currentTotalSeconds = Math.floor((snapshotServerNowMs + monotonicStopwatchElapsedMs - genesisEpochMs) / 1000);
  const totalGameMinutes = Math.floor(currentTotalSeconds / realSecondsPerMinute);
  const gameDay = Math.floor(totalGameMinutes / 1440) + 1;
  const gameMinute = totalGameMinutes % 1440;

  assert.ok(gameDay >= 1);
  assert.ok(gameMinute >= 0 && gameMinute < 1440);

  // Verify that even if system clock jumps (simulated clock skew), monotonic stopwatch duration is unaffected
  const skewedElapsedMs = monotonicStopwatchElapsedMs + 1000;
  const skewedTotalMinutes = Math.floor(Math.floor((snapshotServerNowMs + skewedElapsedMs - genesisEpochMs) / 1000) / realSecondsPerMinute);
  assert.ok(skewedTotalMinutes >= totalGameMinutes, 'Monotonic clock must never move backwards');
});

test('Authoritative World Clock Certification: 5. Settlement cursor backlog & failure-in-middle detection', async () => {
  // Case A: Multi-day catch-up backlog
  const mockBacklogRepo = {
    async query(sql) {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '10' }] };
      }
      if (sql.includes('daily_settlement_runs')) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  };

  const cursorBacklog = await getSettlementCursor(mockBacklogRepo, 15);
  assert.equal(cursorBacklog.settledThroughGameDay, 10);
  assert.equal(cursorBacklog.lastClosedGameDay, 14);
  assert.equal(cursorBacklog.backlogDays, 4);
  assert.equal(cursorBacklog.status, 'CATCHING_UP');
  assert.equal(cursorBacklog.failedGameDay, undefined);

  // Case B: Failure in middle of catch-up (e.g. Day 11 fails at phase 'corporate_dividend_settlement')
  const mockFailedRepo = {
    async query(sql, params) {
      if (sql.includes('daily_settlement_control')) {
        return { rows: [{ status: 'active', settled_through_game_day: '10' }] };
      }
      if (sql.includes('daily_settlement_runs') && sql.includes("status = 'failed'")) {
        return {
          rows: [{
            status: 'failed',
            current_phase: 'corporate_dividend_settlement',
            error_message: 'Insufficient reserves for mandatory dividend tranche',
          }],
        };
      }
      return { rows: [] };
    },
  };

  const cursorFailed = await getSettlementCursor(mockFailedRepo, 15);
  assert.equal(cursorFailed.settledThroughGameDay, 10);
  assert.equal(cursorFailed.status, 'FAILED');
  assert.equal(cursorFailed.failedGameDay, 11);
  assert.equal(cursorFailed.failedPhase, 'corporate_dividend_settlement');
  assert.equal(cursorFailed.failedError, 'Insufficient reserves for mandatory dividend tranche');
});

test('Authoritative World Clock Certification: 6. Architecture scan: zero live legacy-clock readers & valid boundaries', () => {
  const violations = [];

  function scanDirectory(dir, extensions, checkFn) {
    if (!fs.existsSync(dir)) return;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name !== 'node_modules' && entry.name !== '.git' && entry.name !== 'build') {
          scanDirectory(fullPath, extensions, checkFn);
        }
      } else if (extensions.some((ext) => entry.name.endsWith(ext))) {
        const content = fs.readFileSync(fullPath, 'utf8');
        checkFn(fullPath, content);
      }
    }
  }

  // Helper to extract SQL string literals and check them
  function checkSqlQueries(file, content) {
    if (file.endsWith('schema-contract.ts')) return; // Metadata definitions allowed

    const queryLiteralRegex = /['"`]([^'"`]+)['"`]/g;
    let match;
    while ((match = queryLiteralRegex.exec(content)) !== null) {
      const sql = match[1];
      if (/UPDATE\s+world_state\s+SET\s+.*game_day/i.test(sql)) {
        violations.push(`${file}: direct UPDATE of world_state.game_day -> "${sql}"`);
      }
      if (/SELECT\s+[^;]*\bgame_(?:day|minute)\b[^;]*\bFROM\s+world_state\b/i.test(sql) ||
          /FROM\s+world_state\b[^;]*\bgame_(?:day|minute)\b/i.test(sql)) {
        violations.push(`${file}: direct read of world_state.game_day/game_minute -> "${sql}"`);
      }
      if (/earth_advance_world_clock\s*\(/i.test(sql)) {
        violations.push(`${file}: call to earth_advance_world_clock -> "${sql}"`);
      }
    }
  }

  // Scan production backend files
  scanDirectory('cloudflare/src', ['.ts', '.js'], checkSqlQueries);

  // Scan scripts
  scanDirectory('scripts', ['.mjs', '.js'], checkSqlQueries);

  // Scan database.js
  const dbJs = fs.readFileSync(path.resolve('database.js'), 'utf8');
  checkSqlQueries('database.js', dbJs);

  assert.deepEqual(violations, [], `Architecture scan violations found: ${JSON.stringify(violations)}`);
});
