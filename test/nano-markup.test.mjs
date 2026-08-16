import test from 'node:test';
import assert from 'node:assert/strict';
import { toNanoMarkup, fromNanoMarkup } from '../cloudflare/src/nano-markup.ts';

test('toNanoMarkup encodes objects and arrays to valid Nano Markup strings', () => {
  const obj = {
    title: 'Constitutional Charter',
    active: 'true',
    terms: {
      quorum: '0.6',
      taxRate: '0.05',
    },
  };

  const encoded = toNanoMarkup(obj);
  assert.ok(encoded.startsWith('..'), 'Root mapping should start with ..');
  assert.ok(encoded.includes('title Constitutional Charter'));

  const decoded = fromNanoMarkup(encoded);
  assert.equal(decoded.title, 'Constitutional Charter');
  assert.equal(decoded.terms.quorum, '0.6');
});

test('fromNanoMarkup parses both Nano Markup and legacy JSON gracefully', () => {
  const nanoStr = '..\n    cityId CITY-0084\n    taxRate 500';
  const parsedNano = fromNanoMarkup(nanoStr);
  assert.equal(parsedNano.cityId, 'CITY-0084');
  assert.equal(parsedNano.taxRate, '500');

  const jsonStr = JSON.stringify({ cityId: 'CITY-0084', taxRate: 500 });
  const parsedJson = fromNanoMarkup(jsonStr);
  assert.equal(parsedJson.cityId, 'CITY-0084');
  assert.equal(parsedJson.taxRate, 500);
});
