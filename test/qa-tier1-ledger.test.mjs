import test from 'node:test';
import assert from 'node:assert/strict';

function issueShares({ cash, shares, issued, price }) {
  assert.ok(issued > 0 && price >= 0);
  return { cash: cash + issued * price, shares: shares + issued };
}

test('Tier 1 ledger: share issuance adds cash and dilutes ownership without phantom currency', () => {
  const company = issueShares({ cash: 10_000, shares: 1_000, issued: 1_000, price: 12 });
  assert.equal(company.cash, 22_000);
  assert.equal(company.shares, 2_000);
  assert.equal(1_000 / company.shares, 0.5);
});

test('Tier 1 ledger: double-entry transfer preserves total credits', () => {
  const accounts = { buyer: 500, seller: 100, escrow: 0 };
  const amount = 75;
  accounts.buyer -= amount;
  accounts.seller += amount;
  assert.equal(Object.values(accounts).reduce((sum, value) => sum + value, 0), 600);
  assert.ok(Object.values(accounts).every((value) => value >= 0));
});
