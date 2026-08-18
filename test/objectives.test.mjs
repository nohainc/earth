import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluatePlayerObjectives } from '../cloudflare/src/objectives.ts';

test('Player Strategic Objectives Engine', async (t) => {
  await t.test('evaluates all 7 required long-term player objectives', () => {
    const objectives = evaluatePlayerObjectives({
      human: { credits: 12000, standing: 85, legacy: 300, voting_weight: 12.5 },
      business: { id: 'b-1', valuation: 45000, profit: 500 },
      institutions: {
        city: { essential_services_index: 0.85, standing: 80 },
        corporation: { treasury: 25000, member_count: 50 },
      },
      governance: { voting_weight: 12.5 },
      technology: { active_patents: 2, active_licenses: 3 },
      dynasty: { generation: 2, perks_count: 2, successor_id: 'H-0099' },
      map: { plots_leased: 3 },
      resources: { material: 120 },
      netWorth: 28000,
    });

    assert.equal(objectives.length, 7);

    const ids = objectives.map((o) => o.id);
    assert.ok(ids.includes('obj-valuable-corporation'));
    assert.ok(ids.includes('obj-civic-delegate'));
    assert.ok(ids.includes('obj-regional-resource-control'));
    assert.ok(ids.includes('obj-dynasty-traits'));
    assert.ok(ids.includes('obj-technology-licensor'));
    assert.ok(ids.includes('obj-financial-independence'));
    assert.ok(ids.includes('obj-public-service-score'));

    for (const obj of objectives) {
      assert.ok(obj.id);
      assert.ok(obj.title);
      assert.ok(obj.description);
      assert.ok(typeof obj.currentValue === 'number');
      assert.ok(typeof obj.targetValue === 'number');
      assert.ok(typeof obj.progressPercentage === 'number');
      assert.ok(obj.progressPercentage >= 0 && obj.progressPercentage <= 100);
      assert.ok(obj.metricLabel);
      assert.ok(['in_progress', 'completed', 'claimed'].includes(obj.status));
      assert.ok(obj.rewardDescription);
      assert.ok(obj.targetSection);
      assert.ok(obj.iconName);
    }
  });

  await t.test('detects completed objectives when thresholds are reached', () => {
    const objectives = evaluatePlayerObjectives({
      human: { credits: 100000, standing: 98, voting_weight: 30 },
      business: { valuation: 150000, profit: 5000 },
      institutions: {
        city: { essential_services_index: 0.95, standing: 95 },
      },
      governance: { voting_weight: 30 },
      technology: { active_patents: 4, active_licenses: 4 },
      dynasty: { generation: 3, perks_count: 4, successor_id: 'H-0099' },
      map: { plots_leased: 6 },
      resources: { material: 500 },
      netWorth: 80000,
    });

    assert.equal(objectives.length, 7);
    assert.ok(objectives.some((o) => o.status === 'completed'));

    const corpObj = objectives.find((o) => o.id === 'obj-valuable-corporation');
    assert.equal(corpObj.status, 'completed');
    assert.equal(corpObj.progressPercentage, 100);

    const financeObj = objectives.find((o) => o.id === 'obj-financial-independence');
    assert.equal(financeObj.status, 'completed');
    assert.equal(financeObj.progressPercentage, 100);
  });
});
