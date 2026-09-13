import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');

function filesUnder(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(file) : [file];
  });
}

test('removed briefing, telemetry, and edge event implementations stay deleted', () => {
  for (const relative of [
    'cloudflare/src/daily-briefing-postgres.ts',
    'cloudflare/src/engines/ai-briefing-engine.ts',
    'cloudflare/src/error-logger-postgres.ts',
  ]) {
    assert.equal(fs.existsSync(path.join(root, relative)), false, `${relative} must remain deleted`);
  }
});

test('active runtime contains no retired endpoint or implementation references', () => {
  const directories = [path.join(root, 'cloudflare', 'src'), path.join(root, 'flutter_client', 'lib')];
  const forbidden = /\/edge\/events|\/api\/player\/daily-briefing|app_error_logs|ai-briefing-engine|DailyBriefing|daily-briefing/i;
  const violations = [];
  for (const directory of directories) {
    for (const file of filesUnder(directory).filter((candidate) => /\.(ts|dart)$/.test(candidate))) {
      if (forbidden.test(fs.readFileSync(file, 'utf8'))) violations.push(path.relative(root, file));
    }
  }
  assert.deepEqual(violations, [], 'Remove retired architecture references from active runtime code');
});
