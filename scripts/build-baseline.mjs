import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('../', import.meta.url).pathname;
const baselineDir = join(root, 'db', 'baseline');
const output = join(root, 'db', 'migrations', '001_baseline.sql');
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
await writeFile(output, `${outputParts.join('\n')}\n`);
console.log(`Generated ${output}`);
