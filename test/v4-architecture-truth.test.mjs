import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('V4 architecture freeze is present and aligned with the canonical model', () => {
  const target = read('docs/V4_TARGET_ARCHITECTURE.md');
  const model = read('docs/V4_DOMAIN_MODEL.md');
  for (const term of ['EARTH', 'House', 'Human', 'Territory', 'Organization', 'CREDIT', 'PostgreSQL']) {
    assert.match(target, new RegExp(`\\b${term}\\b`), `target architecture is missing ${term}`);
    assert.match(model, new RegExp(`\\b${term}\\b`), `domain model is missing ${term}`);
  }
  assert.match(target, /Corporation and Community are\s+transitional Organization archetypes/);
  assert.match(target, /Durable Objects coordinate delivery and sockets only/);
  assert.match(target, /Day close occurs only after the required barrier is complete/);
});

test('V4 documentation index identifies the architecture freeze as canonical', () => {
  const status = read('docs/DOCUMENT_STATUS.md');
  assert.match(status, /`V4_TARGET_ARCHITECTURE\.md`\s*\|\s*CANONICAL/);
  assert.match(status, /`V4_DOMAIN_MODEL\.md`\s*\|\s*CANONICAL/);
  assert.match(status, /`V4_IMPLEMENTATION_STATUS\.md`\s*\|\s*CANONICAL/);
});

test('clean baseline and migration manifest remain frozen and contiguous', () => {
  const baseline = read('db/migrations/001_baseline.sql');
  assert.match(baseline, /EARTH ACTIVE MIGRATION: clean baseline/);
  assert.match(read('db/migrations/001_baseline.sha256'), /^[a-f0-9]{64}/);
  const manifest = JSON.parse(read('db/schema-manifest.json'));
  assert.equal(manifest.baseline, 'db/baseline/001_baseline.sql');
  assert.equal(manifest.migrationVersion, 79);
});
