import { readFile, writeFile } from 'node:fs/promises';

const schema = await readFile(new URL('../db/baseline/01_schema.sql', import.meta.url), 'utf8');
const functions = await readFile(new URL('../db/baseline/02_functions.sql', import.meta.url), 'utf8');

function splitDefinitions(source) {
  const definitions = [];
  for (const match of source.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\);/gi)) {
    const columns = [];
    let depth = 0;
    let token = '';
    for (const char of match[2]) {
      if (char === '(') depth += 1;
      if (char === ')') depth -= 1;
      if (char === ',' && depth === 0) {
        const name = token.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s+/i)?.[1];
        if (name) columns.push(name);
        token = '';
      } else token += char;
    }
    const name = token.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s+/i)?.[1];
    if (name) columns.push(name);
    definitions.push([match[1], [...new Set(columns)]]);
  }
  return definitions;
}

const requiredTables = Object.fromEntries(splitDefinitions(schema));
const requiredUniqueConstraints = [];
for (const [table, body] of schema.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\);/gi)) {
  for (const match of body.matchAll(/(?:^|,)\s*(?:CONSTRAINT\s+[a-z_][a-z0-9_]*\s+)?UNIQUE\s*\(([^)]+)\)/gim)) {
    requiredUniqueConstraints.push([table, ...match[1].split(',').map((column) => column.trim())]);
  }
}
const requiredIndexes = [...schema.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+([a-z_][a-z0-9_]*)/gi)].map((match) => match[1]);
const requiredFunctions = [...functions.matchAll(/CREATE OR REPLACE FUNCTION\s+([a-z_][a-z0-9_]*)/gi)].map((match) => match[1]);

const manifest = {
  manifestVersion: 1,
  migrationVersion: 1,
  baseline: 'db/baseline/001_baseline.sql',
  requiredTables,
  requiredUniqueConstraints,
  requiredIndexes,
  requiredFunctions,
};
await writeFile(new URL('../db/schema-manifest.json', import.meta.url), `${JSON.stringify(manifest, null, 2)}\n`);
