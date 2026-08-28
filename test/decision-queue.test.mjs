import test from 'node:test';
import assert from 'node:assert/strict';
import { generateDecisionQueue } from '../cloudflare/src/decision-queue.ts';

test('Unified Decision Queue Generator', async (t) => {
  await t.test('generates prioritized items for corporate energy loss, expiring contracts, governance, research, and house', () => {
    const queue = generateDecisionQueue({
      resources: { energy: 15, material: 80 },
      contracts: [{ id: 'c-101', title: 'Components Supply', status: 'active' }],
      proposals: [{ id: 'prop-12', title: 'City Tax Charter Amendment', status: 'open' }],
      technology: { progress: 50 },
      house: { successor_id: null, perks_available: true },
      business: { id: 'b-1', name: 'AeroCorp', profit: -200 },
      finance: { unpaid_tax: 150 },
      market: [{ product: 'food', supply: 10, demand: 45, price: 12 }],
      city: { id: 'CITY-0084', residents: 100, energy_capacity: 60, health_capacity: 35 },
      gameDay: 185,
    });

    assert.ok(queue.length >= 6);

    // Verify all 6 required items exist
    const titles = queue.map((item) => item.title);
    assert.ok(titles.some((t) => t.includes('losing energy')));
    assert.ok(titles.some((t) => t.includes('contract expires in 2 days')));
    assert.ok(titles.some((t) => t.includes('unresolved governance vote')));
    assert.ok(titles.some((t) => t.includes('Research funding is available')));
    assert.ok(titles.some((t) => t.includes('house decision is pending')));
    assert.ok(titles.some((t) => t.includes('Legacy points can unlock')));
    assert.ok(titles.some((t) => t.includes('city needs an energy recovery plan')));
    assert.ok(titles.some((t) => t.includes('city needs a health recovery plan')));

    // Check properties of each item
    for (const item of queue) {
      assert.ok(item.id);
      assert.ok(item.category);
      assert.ok(item.title);
      assert.ok(item.whyItMatters);
      assert.ok(item.deadline);
      assert.ok(item.expectedImpact);
      assert.ok(['critical', 'high', 'medium', 'low'].includes(item.riskLevel));
      assert.ok(item.primaryActionLabel);
      assert.ok(item.targetSection);
      assert.ok(typeof item.urgencyScore === 'number');
    }

    // Critical/High risk items should be sorted first
    assert.equal(queue[0].riskLevel, 'critical');
  });

  await t.test('handles empty or clean state gracefully', () => {
    const queue = generateDecisionQueue({
      resources: { energy: 100, material: 100 },
      machines: [{ id: 'm-1', condition: 95 }],
      contracts: [],
      proposals: [],
      technology: { progress: 100 },
      house: { successor_id: 'H-0099' },
      business: { profit: 500 },
      finance: { unpaid_tax: 0 },
      market: [],
    });

    // In a completely healthy state, only low-priority/no urgent items
    assert.ok(queue.every((item) => item.riskLevel !== 'critical'));
  });
});
