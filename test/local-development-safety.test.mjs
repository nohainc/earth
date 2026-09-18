import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('local launcher fails closed for remote live scheduler use', () => {
  const launcher = fs.readFileSync(path.resolve('scripts/run-local-ui-test.sh'), 'utf8');
  assert.match(launcher, /EARTH_LOCAL_MODE/);
  assert.match(launcher, /REFUSING TO START/);
  assert.match(launcher, /EARTH_ALLOW_REMOTE_MUTATION/);
  assert.match(launcher, /sleep \\\$\(\(60 - \\\$\(date \+%s\) % 60\)\)/);
});

test('local development uses heartbeat/status commands and does not mutate the clock', () => {
  const baseline = fs.readFileSync(path.resolve('db/migrations/001_baseline.sql'), 'utf8');
  const dropMigration = fs.readFileSync(path.resolve('db/migrations/131_drop_world_state_legacy_game_time_columns.sql'), 'utf8');
  const command = fs.readFileSync(path.resolve('scripts/local-game-command.mjs'), 'utf8');
  assert.match(dropMigration, /DROP FUNCTION IF EXISTS earth_advance_world_clock/);
  assert.doesNotMatch(command, /earth_advance_world_clock|advance-hour|advance-day/);
  assert.match(command, /heartbeat/);
  assert.match(command, /status \| time \| heartbeat/);
  assert.match(command, /Refusing local game command against a remote/);
});
