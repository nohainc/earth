import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('derivative positions resolve through the House economic owner', () => {
  const api = read('cloudflare/src/market-api.ts');
  const derivatives = read('cloudflare/src/derivatives-postgres.ts');
  const expiry = read('cloudflare/src/market-futures-settlement.ts');

  assert.match(api, /derivative_obligations[\s\S]*COALESCE\(\(SELECT house_id FROM humans WHERE id = \$1\), \$1\)/);
  assert.match(derivatives, /derivative_obligations[\s\S]*COALESCE\(\(SELECT house_id FROM humans WHERE id = \$2\), \$2\)/);
  assert.match(expiry, /long_owner_economic_id/);
  assert.match(expiry, /short_owner_economic_id/);
  assert.match(expiry, /long_escrow_account_id/);
  assert.match(expiry, /short_escrow_account_id/);
  assert.doesNotMatch(expiry, /humans|successor|death/i);
});
