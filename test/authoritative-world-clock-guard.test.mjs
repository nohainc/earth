import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('architecture guard: no production code advances world_state.game_day directly', () => {
  const srcDir = path.resolve('cloudflare/src');
  const files = fs.readdirSync(srcDir).filter((f) => f.endsWith('.ts'));

  const violations = [];
  for (const file of files) {
    const content = fs.readFileSync(path.join(srcDir, file), 'utf8');

    // Disallow UPDATE world_state SET game_day
    if (/UPDATE\s+world_state\s+SET\s+.*game_day/i.test(content)) {
      violations.push(`${file}: direct UPDATE of world_state.game_day detected`);
    }

    // Disallow calls to earth_advance_world_clock in cloudflare/src (except possibly legacy schema definitions)
    if (/earth_advance_world_clock\s*\(/i.test(content)) {
      violations.push(`${file}: call to earth_advance_world_clock detected`);
    }
  }

  assert.deepEqual(violations, [], 'Direct game clock manipulation violations found');
});

test('architecture guard: no production code reads world_state.game_day or world_state.game_minute directly', () => {
  const srcDir = path.resolve('cloudflare/src');
  const files = fs.readdirSync(srcDir).filter((f) => f.endsWith('.ts'));

  const violations = [];
  for (const file of files) {
    // schema-contract.ts defines DB column names for the schema contract, allow it
    if (file === 'schema-contract.ts') continue;
    const content = fs.readFileSync(path.join(srcDir, file), 'utf8');

    // Disallow SELECT ... game_day / game_minute FROM world_state
    if (/SELECT\s+[^;]*\bgame_(?:day|minute)\b[^;]*\bFROM\s+world_state\b/i.test(content) ||
        /FROM\s+world_state\b[^;]*\bgame_(?:day|minute)\b/i.test(content) ||
        /\bworld_state\.game_(?:day|minute)\b/i.test(content)) {
      violations.push(`${file}: direct read of world_state.game_day/game_minute detected`);
    }
  }

  assert.deepEqual(violations, [], 'Direct game clock read violations found');
});

test('architecture guard: scheduler is decoupled from game clock advancement', () => {
  const schedulerSrc = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.doesNotMatch(schedulerSrc, /earth_advance_world_clock/);
  assert.match(schedulerSrc, /readAuthoritativeGameTime/);
  assert.match(schedulerSrc, /getSettlementCursor/);
  assert.match(schedulerSrc, /lastClosedGameDay/);
});

test('architecture guard: world API exposes canonical clock and settlement schemas', () => {
  const worldSrc = fs.readFileSync(path.resolve('cloudflare/src/world-postgres.ts'), 'utf8');
  assert.match(worldSrc, /const clock = await readAuthoritativeGameTime/);
  assert.match(worldSrc, /getSettlementCursor\(repository,\s*clock\.gameDay\)/);
  assert.match(worldSrc, /settledThroughGameDay/);
  assert.match(worldSrc, /lastClosedGameDay/);
  assert.match(worldSrc, /backlogDays/);
});

test('architecture guard: migration 130 defines canonical authoritative clock and settlement cursor', () => {
  const migPath = path.resolve('db/migrations/130_authoritative_world_clock.sql');
  assert.ok(fs.existsSync(migPath), 'Migration 130 must exist');

  const content = fs.readFileSync(migPath, 'utf8');
  assert.match(content, /genesis_at TIMESTAMPTZ/);
  assert.match(content, /trg_world_genesis_immutability/);
  assert.match(content, /settled_through_game_day BIGINT/);
  assert.match(content, /earth_get_current_game_time/);
  assert.match(content, /earth_advance_settlement_cursor/);
});

test('architecture guard: mandatory daily actions execute inside settlement boundary', () => {
  const schedulerSrc = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const phasesSrc = fs.readFileSync(path.resolve('cloudflare/src/daily-settlement-phases.ts'), 'utf8');

  // Verify house_policy_execution is a required settlement phase
  assert.match(phasesSrc, /required\('house_policy_execution'/);
  assert.match(schedulerSrc, /housePolicyExecution:\s*async\s*\(\{ tx, day, shard, shardCount \}\)\s*=>\s*executeHousePoliciesForDay/);

  // Verify executeHousePoliciesForDay is not called directly in runWorldSchedulerTick
  const tickBody = schedulerSrc.slice(schedulerSrc.indexOf('function runWorldSchedulerTick'));
  assert.doesNotMatch(tickBody, /executeHousePoliciesForDay\s*\(/);
});

