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

test('manual clock is explicit and developer commands do not expose public routes', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/185_local_manual_clock.sql'), 'utf8');
  const command = fs.readFileSync(path.resolve('scripts/local-game-command.mjs'), 'utf8');
  assert.match(migration, /clock_mode[\s\S]*'manual'/);
  assert.match(migration, /earth_local_advance_minutes/);
  assert.match(command, /earth_local_advance_minutes/);
  assert.match(command, /Refusing local game command against a remote/);
});
