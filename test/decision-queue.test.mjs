import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { generateDecisionQueue } from '../cloudflare/src/decision-queue.ts';

test('decision queue engine is V5-only', async () => {
  const source = await readFile(new URL('../cloudflare/src/decision-queue.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\b(territory|territories|organization|city|machines|heirloom|perk)\b/i);
  assert.doesNotMatch(source, /successor_id/);
});

test('Unified Decision Queue Generator', async (t) => {
  await t.test('generates prioritized items for house needs, buildings, finance, governance, succession, research, and market', () => {
    const queue = generateDecisionQueue({
      gameDay: 185,
      needs: [{ need_code: 'ENERGY', demand_units: 100, allocated_units: 20, shortfall_units: 80, risk_level: 'critical' }],
      buildings: [
        { id: 'b-suspended', status: 'SUSPENDED', v5_productive_status: 'SUSPENDED' },
        { id: 'b-under', status: 'ACTIVE', utilization_bps: 4000, latest_settlement_status: 'SHORTFALL' },
      ],
      finance: { unpaid_tax: 150, capacity_arrears_units: 500, delinquency_status: 'DELINQUENT' },
      proposals: [{ id: 'prop-12', title: 'Constitutional Tax Rate', status: 'open' }],
      house: { has_successor: false },
      technology: { progress: 50 },
      market: [{ product: 'food', supply: 10, demand: 45, price: 12 }],
      orders: { open_count: 2, expiring_count: 1 },
    });

    assert.ok(queue.length >= 6);

    // Verify expected V5 items exist
    const titles = queue.map((item) => item.title);
    assert.ok(titles.some((t) => t.includes('House ENERGY access')));
    assert.ok(titles.some((t) => t.includes('building is suspended')));
    assert.ok(titles.some((t) => t.includes('operating below capacity')));
    assert.ok(titles.some((t) => t.includes('capacity rent requires urgent settlement')));
    assert.ok(titles.some((t) => t.includes('unresolved governance vote')));
    assert.ok(titles.some((t) => t.includes('house decision is pending')));
    assert.ok(titles.some((t) => t.includes('Research funding is available')));
    assert.ok(titles.some((t) => t.includes('shortage on Central Market')));
    assert.ok(titles.some((t) => t.includes('nearing expiry')));

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
    assert.ok(['citizen', 'buildings', 'finance', 'governance', 'house', 'technology', 'market'].includes(item.targetRoute));
    assert.equal(typeof item.viewerCanAct, 'boolean');
      assert.ok(typeof item.urgencyScore === 'number');
    }

    // Critical/High risk items should be sorted first
    assert.equal(queue[0].riskLevel, 'critical');
  });

  await t.test('handles empty or clean state gracefully', () => {
    const queue = generateDecisionQueue({
      gameDay: 185,
      needs: [{ need_code: 'ENERGY', demand_units: 100, allocated_units: 100, shortfall_units: 0, risk_level: 'normal' }],
      buildings: [{ id: 'b-1', status: 'ACTIVE', utilization_bps: 10000, latest_settlement_status: 'NORMAL' }],
      finance: { unpaid_tax: 0, capacity_arrears_units: 0, delinquency_status: 'CURRENT' },
      proposals: [],
      house: { has_successor: true },
      technology: { progress: 100 },
      market: [],
    });

    // In a completely healthy state, no critical items
    assert.ok(queue.every((item) => item.riskLevel !== 'critical'));
  });

  await t.test('a registered successor produces no succession warning', () => {
    const queue = generateDecisionQueue({
      house: { has_successor: true },
      technology: { progress: 100 },
      market: [],
    });
    assert.equal(queue.some((item) => item.id === 'decision-house-successor-pending'), false);
  });

  await t.test('emits V5 facts for capacity arrears, utilization, governance, and all market commodities', () => {
    const products = ['energy', 'food', 'materials', 'components', 'compute'];
    const queue = generateDecisionQueue({
      finance: { capacity_arrears_units: '12500', delinquency_status: 'DELINQUENT' },
      buildings: [{ id: 'building-1', status: 'ACTIVE', utilization_bps: 4200, latest_settlement_status: 'SHORTFALL' }],
      proposals: [{ id: 'proposal-1', title: 'Capacity policy', status: 'VOTING', viewer: { canVote: true } }],
      house: { has_successor: true },
      technology: { progress: 100 },
      market: products.map((product) => ({ product, supply: 1, demand: 20, price: '12500' })),
    });
    assert.ok(queue.some((item) => item.id === 'decision-finance-capacity-arrears'));
    assert.ok(queue.some((item) => item.id === 'decision-building-utilization-building-1'));
    assert.ok(queue.some((item) => item.id === 'decision-governance-vote-proposal-1'));
    for (const product of products) {
      assert.ok(queue.some((item) => item.id === `decision-market-shortage-${product}`));
    }
    assert.equal(queue.find((item) => item.id === 'decision-governance-vote-proposal-1').viewerCanAct, true);
    assert.deepEqual([...new Set(queue.map((item) => item.targetRoute))].sort(), ['buildings', 'finance', 'governance', 'market']);
  });

  await t.test('does not invent a CREDIT display conversion in queue copy', () => {
    const queue = generateDecisionQueue({
      finance: { capacity_arrears_units: '12500', delinquency_status: 'DELINQUENT' },
      house: { has_successor: true },
    });
    const item = queue.find((entry) => entry.id === 'decision-finance-capacity-arrears');
    assert.ok(item);
    assert.doesNotMatch(item.whyItMatters, /12500\s*CREDIT/);
  });
});
