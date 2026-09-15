import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('V4 long-horizon certification covers 10, 30, and 100 year horizons', async () => {
  const source = await readFile(new URL('../scripts/certify-v4-long-horizon.mjs', import.meta.url), 'utf8');
  for (const horizon of ['10', '30', '100']) assert.match(source, new RegExp(horizon));
  assert.match(source, /deterministic/);
  assert.match(source, /shortageFrequency/);
  assert.match(source, /wealthConcentration/);
});
