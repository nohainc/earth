import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const sourceRoot = path.resolve('cloudflare/src');
const files = fs.readdirSync(sourceRoot)
  .filter((file) => file.endsWith('.ts'))
  .map((file) => path.join(sourceRoot, file));

test('economic transaction timestamps are posted only through the canonical helper', () => {
  const directPosters = files.filter((file) => {
    if (path.basename(file) === 'economic-transaction-postgres.ts') return false;
    return /earth_post_transaction\s*\(/.test(fs.readFileSync(file, 'utf8'));
  });

  assert.deepEqual(directPosters, [], 'Production economic code must use postEconomicTransaction or postSettlementTransaction');
});

test('end-of-day minute 1439 is restricted to explicit settlement or clock arithmetic', () => {
  const allowedFiles = new Set([
    'economic-transaction-postgres.ts',
    'world-clock-postgres.ts',
    'daily-automation.ts',
    'global-bank-settlement-engine.ts',
  ]);
  const unexplained = files.filter((file) => {
    if (allowedFiles.has(path.basename(file))) return false;
    return /\b1439\b/.test(fs.readFileSync(file, 'utf8'));
  });

  assert.deepEqual(unexplained, [], 'Interactive production paths must not hard-code the end-of-day timestamp');
});
