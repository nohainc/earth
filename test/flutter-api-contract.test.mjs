import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const files = fs.readdirSync(new URL('../flutter_client/lib/core/api/', import.meta.url))
  .filter((file) => file.startsWith('earth_api') && file.endsWith('.dart'))
  .map((file) => fs.readFileSync(new URL(`../flutter_client/lib/core/api/${file}`, import.meta.url), 'utf8'));
const source = files.join('\n');

test('Flutter API layer uses canonical server paths only', () => {
  for (const retired of [
    '/api/finance/personal',
    '/api/market/settle',
    '/api/corporate-research/',
    '/api/corporation/building-research',
    '/api/corporations/building-research',
    '/api/technology/adopt',
    '/api/technology/share',
    '/api/human/successor/settle',
  ]) assert.doesNotMatch(source, new RegExp(retired.replaceAll('/', '\\/')));
  assert.match(source, /['"]\/api\/finance\/me['"]/);
  assert.match(source, /['"]\/api\/market\/orders['"]/);
  assert.match(source, /['"]\/api\/research\/buildings['"]/);
});

test('account deletion sends explicit confirmation to the protected endpoint', () => {
  const auth = fs.readFileSync(new URL('../flutter_client/lib/core/api/earth_api_auth.dart', import.meta.url), 'utf8');
  assert.match(auth, /'confirm': true/);
  assert.match(auth, /\/api\/auth\/account/);
});
