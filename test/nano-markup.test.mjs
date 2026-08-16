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

test('parseJsonBody parses application/nanomarkup requests seamlessly', async () => {
  const { parseJsonBody } = await import('../cloudflare/src/request-validation.ts');
  const nanoBody = '..\n    product energy\n    quantity 10\n    limitPrice 0.85';
  const request = new Request('https://earthuc.com/api/market/orders', {
    method: 'POST',
    headers: {
      'content-type': 'application/nanomarkup',
      'accept': 'application/nanomarkup',
    },
    body: nanoBody,
  });

  const parsed = await parseJsonBody(request);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.product, 'energy');
  assert.equal(parsed.value.quantity, '10');
  assert.equal(parsed.value.limitPrice, '0.85');
});

