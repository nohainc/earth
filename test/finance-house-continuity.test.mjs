import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Finance V2 banking contracts resolve Human requests to House owners', () => {
  const deposits = read('db/migrations/215_bank_deposits_v2.sql');
  const loans = read('db/migrations/216_bank_loans_v2.sql');
  const bank = read('cloudflare/src/global-bank-postgres.ts');
  const routes = read('cloudflare/src/finance-routes.ts');

  assert.match(deposits, /earth_private_economic_owner_id\(p_human_id\)/);
  assert.match(loans, /o\.owner_type = 'house'/);
  assert.match(loans, /borrower\.owner_type IN \('human', 'house'\)/);
  assert.match(bank, /earth_create_v2_bank_deposit/);
  assert.match(bank, /earth_withdraw_bank_deposit/);
  assert.match(routes, /bank_deposits[\s\S]*WHERE o\.id = \$1[\s\S]*viewer\.house_id/);
});
