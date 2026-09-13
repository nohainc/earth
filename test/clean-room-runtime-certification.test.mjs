import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('clean-room runtime certification is available as an explicit command', () => {
  const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  assert.match(packageJson.scripts['test:clean-room-runtime'], /certify-clean-room-runtime/);
  assert.match(fs.readFileSync('scripts/certify-clean-room-runtime.mjs', 'utf8'), /EARTH_CLEAN_ROOM_API_ORIGIN/);
  assert.match(fs.readFileSync('scripts/certify-clean-room-runtime.mjs', 'utf8'), /EARTH_CERTIFICATION_BEARER_TOKEN/);
});
