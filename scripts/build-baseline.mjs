import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../', import.meta.url).pathname;
const baselineDir = join(root, 'db', 'baseline');
const output = join(root, 'db', 'migrations', '001_baseline.sql');
const lockFile = join(root, 'db', 'migrations', '001_baseline.sha256');
const sections = [
  ['SECTION 1: SCHEMA', '01_schema.sql'],
  ['SECTION 2: FUNCTIONS', '02_functions.sql'],
  ['SECTION 3: REFERENCE DATA', '03_reference_data.sql'],
  ['SECTION 4: INITIAL WORLD', '04_initial_world.sql'],
];
const outputParts = [
  '-- EARTH ACTIVE MIGRATION: clean baseline',
  '-- GENERATED FILE: run npm run db:baseline:build; do not edit directly',
  '',
];
for (const [title, file] of sections) {
  outputParts.push('-- =====================================================', `-- ${title}`, '-- =====================================================', '');
  outputParts.push((await readFile(join(baselineDir, file), 'utf8')).trim(), '');
}
const generated = `${outputParts.join('\n')}\n`;
const expectedChecksum = (await readFile(lockFile, 'utf8')).trim().split(/\s+/)[0];
const checksum = createHash('sha256').update(generated).digest('hex');
if (checksum !== expectedChecksum) {
  throw new Error('Migration 001 is frozen; create a new forward migration instead of regenerating it');
}
const current = await readFile(output, 'utf8');
if (current !== generated) {
  throw new Error('Migration 001 differs from its frozen baseline; restore it or create a new forward migration');
}
console.log(`Migration 001 is frozen and verified (${checksum})`);
