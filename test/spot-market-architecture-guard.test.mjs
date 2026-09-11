import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');

function productionFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? productionFiles(file) : [file];
  }).filter((file) => /\.(ts|sql|json|jsonc)$/.test(file));
}

test('Spot Market remains free of retired Futures concepts', () => {
  const files = [
    ...productionFiles(path.join(root, 'cloudflare', 'src')),
    path.join(root, 'db', 'schema.sql'),
    path.join(root, 'db', 'schema-manifest.json'),
  ];
  const forbidden = /DELIVERY_FUTURE|FEATURE_FUTURES|derivative_obligations|market-futures|derivatives-postgres|settleExpiredFutureInstrument/i;
  for (const file of files) {
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), forbidden, `${path.relative(root, file)} reintroduced a retired Futures concept`);
  }
});

