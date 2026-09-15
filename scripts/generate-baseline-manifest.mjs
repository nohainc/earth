import { readdir, readFile, writeFile } from 'node:fs/promises';

const schema = await readFile(new URL('../db/baseline/01_schema.sql', import.meta.url), 'utf8');
const functions = await readFile(new URL('../db/baseline/02_functions.sql', import.meta.url), 'utf8');

function splitDefinitions(source) {
  const definitions = [];
  const tableConstraintKeywords = new Set(['PRIMARY', 'UNIQUE', 'CHECK', 'CONSTRAINT', 'EXCLUDE', 'FOREIGN']);
  for (const match of source.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\);/gi)) {
    const columns = [];
    let depth = 0;
    let token = '';
    for (const char of match[2]) {
      if (char === '(') depth += 1;
      if (char === ')') depth -= 1;
      if (char === ',' && depth === 0) {
        const name = token.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s+/i)?.[1];
        if (name && !tableConstraintKeywords.has(name.toUpperCase())) columns.push(name);
        token = '';
      } else token += char;
    }
    const name = token.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s+/i)?.[1];
    if (name && !tableConstraintKeywords.has(name.toUpperCase())) columns.push(name);
    definitions.push([match[1], [...new Set(columns)]]);
  }
  return definitions;
}

const requiredTables = Object.fromEntries(splitDefinitions(schema));
const requiredUniqueConstraints = [];
if (/CREATE TABLE economic_transactions[^;]*\bcorrelation_id\s+TEXT\s+NOT NULL\s+UNIQUE\b/i.test(schema)) {
  requiredUniqueConstraints.push(['economic_transactions', 'correlation_id']);
}
for (const [table, body] of schema.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\);/gi)) {
  for (const match of body.matchAll(/(?:^|,)\s*([a-z_][a-z0-9_]*)\s+[^,]*?\bUNIQUE\b/gim)) {
    requiredUniqueConstraints.push([table, match[1]]);
  }
}
for (const [table, body] of schema.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\);/gi)) {
  for (const match of body.matchAll(/(?:^|,)\s*(?:CONSTRAINT\s+[a-z_][a-z0-9_]*\s+)?UNIQUE\s*\(([^)]+)\)/gim)) {
    requiredUniqueConstraints.push([table, ...match[1].split(',').map((column) => column.trim())]);
  }
}
const requiredIndexes = [...schema.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+([a-z_][a-z0-9_]*)/gi)].map((match) => match[1]);
const requiredFunctions = [...functions.matchAll(/CREATE OR REPLACE FUNCTION\s+([a-z_][a-z0-9_]*)/gi)].map((match) => match[1]);
const migrationNames = (await readdir(new URL('../db/migrations/', import.meta.url)))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort((a, b) => Number(a.match(/^\d+/)[0]) - Number(b.match(/^\d+/)[0]));
const activeMigrationVersions = [];
for (const name of migrationNames) {
  if ((await readFile(new URL(`../db/migrations/${name}`, import.meta.url), 'utf8')).includes('-- EARTH ACTIVE MIGRATION:')) {
    activeMigrationVersions.push(Number(name.match(/^\d+/)[0]));
  }
}

const manifest = {
  manifestVersion: 1,
  migrationVersion: activeMigrationVersions.at(-1) ?? 0,
  baseline: 'db/baseline/001_baseline.sql',
  requiredTables,
  requiredUniqueConstraints,
  requiredIndexes,
  requiredFunctions,
};
await writeFile(new URL('../db/schema-manifest.json', import.meta.url), `${JSON.stringify(manifest, null, 2)}\n`);
