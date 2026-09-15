import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('procurement delivery lifecycle gates service-invoice settlement', async () => {
  const performance = await readFile(new URL('../cloudflare/src/contract-performance-postgres.ts', import.meta.url), 'utf8');
  const settlement = await readFile(new URL('../cloudflare/src/credit-settlement-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/070_procurement_delivery_lifecycle.sql', import.meta.url), 'utf8');
  for (const term of ['DELIVERED', 'ACCEPTED', 'DISPUTED', 'delivery_note', 'quality_score_bps']) assert.match(`${performance}\n${migration}`, new RegExp(term));
  assert.match(settlement, /performance\.status !== 'ACCEPTED'/);
  assert.match(settlement, /delivery-pending/);
});
