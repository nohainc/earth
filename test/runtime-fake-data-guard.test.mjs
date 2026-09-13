import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const sourceRoot = path.join(root, 'cloudflare', 'src');

function sourceFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? sourceFiles(file) : [file];
  }).filter((file) => file.endsWith('.ts'));
}

test('Cloudflare runtime contains no known fixture world state', () => {
  const forbidden = [
    /New Geneva/i,
    /Neo Kyoto/i,
    /Valpara[ií]so/i,
    /Aethelgard/i,
    /\bH-0044\b/i,
    /\bCITY-0084\b/i,
    /\bOUC-001\b/i,
    /\bTECH-001\b/i,
    /\bAI Research(?: Grant)?\b/i,
    /\b(?:buildDailyBriefing|aiBriefing)\b/i,
  ];

  const violations = [];
  for (const file of sourceFiles(sourceRoot)) {
    const contents = fs.readFileSync(file, 'utf8');
    for (const pattern of forbidden) {
      if (pattern.test(contents)) violations.push(`${path.relative(root, file)} matches ${pattern}`);
    }
  }
  assert.deepEqual(violations, [], 'Remove fixture values from production handlers');
});

test('runtime price projections do not invent a current market price', () => {
  const readModel = fs.readFileSync(path.join(sourceRoot, 'read-postgres.ts'), 'utf8');
  assert.doesNotMatch(readModel, /price_units\s*\?\?\s*1000/);
});

test('runtime handlers do not inject known placeholder gameplay values', () => {
  const contents = sourceFiles(sourceRoot)
    .map((file) => fs.readFileSync(file, 'utf8'))
    .join('\n');
  assert.doesNotMatch(contents, /gameDay\s*\?\?\s*184/);
  assert.doesNotMatch(contents, /resources\?\.[a-z]+\s*\?\?\s*100/);
  assert.doesNotMatch(contents, /progress\s*\?\?\s*45/);
  assert.doesNotMatch(contents, /body\.(?:budget|amount)\s*\?\?\s*240/);
  assert.doesNotMatch(contents, /equityVal\s*=\s*25000/);
  assert.doesNotMatch(contents, /realEstateVal\s*=\s*15000/);
});
