import test from 'node:test';
import assert from 'node:assert/strict';
import { rankOpportunities } from '../cloudflare/src/opportunities.ts';

test('ranks live market and production signals without changing economic state', () => {
  const opportunities = rankOpportunities({
    market: [
      { product: 'components', supply: '100', demand: '250', price: '118.7' },
      { product: 'energy', supply: '100', demand: '90', price: '0.84' },
    ],
    machines: [{ id: 'M-1', name: 'Fabricator', output_resource: 'components', condition: '86', utilization: '25' }],
    proposals: [{ id: 'P-1', title: 'Maintenance levy', status: 'open' }],
    communities: [{ id: 'C-1', name: 'Common Ground', status: 'active' }],
  });

  assert.equal(opportunities.length, 4);
  assert.equal(opportunities[0].signal, 'production');
  assert.equal(opportunities[1].signal, 'market');
  assert.equal(opportunities[1].subject, 'components');
  assert.equal(opportunities[2].signal, 'governance');
  assert.equal(opportunities[3].signal, 'community');
  assert.equal(opportunities.every((item) => !('score' in item)), true);
});

test('returns no market opportunity when supply meets demand', () => {
  const opportunities = rankOpportunities({
    market: [{ product: 'energy', supply: 100, demand: 100, price: 1 }],
    machines: [],
    proposals: [],
    communities: [],
  });
  assert.deepEqual(opportunities, []);
});

test('caps the command-center list to five signals', () => {
  const opportunities = rankOpportunities({
    market: Array.from({ length: 8 }, (_, index) => ({ product: `resource-${index}`, supply: 1, demand: 10 + index, price: 1 })),
    machines: [],
    proposals: [{ id: 'P-1', title: 'Proposal', status: 'open' }],
    communities: [{ id: 'C-1', name: 'Community', status: 'active' }],
  });
  assert.equal(opportunities.length, 5);
});
