import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/institution-spending.ts', import.meta.url), 'utf8');

test('institution spending consumes the canonical economic posting result', () => {
  assert.doesNotMatch(source, /\bpostingRow\b/);
  assert.match(source, /posting\.transactionId/);
  assert.match(source, /posting\.created/);
});
