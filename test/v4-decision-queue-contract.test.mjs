import test from 'node:test';
import assert from 'node:assert/strict';
import { generateDecisionQueue } from '../cloudflare/src/decision-queue.ts';

test('V4 decision queue is a deterministic read model over Territory and Organization facts', () => {
  const input = {
    resources: { energy: 12, material: 80 },
    territory: { id: 'T-1', residents: 100, energy_capacity: 40, health_capacity: 30 },
    organization: { id: 'ORG-1', profit: -10 },
    house: { successor_id: null },
    gameDay: 42,
  };

  const first = generateDecisionQueue(input);
  const second = generateDecisionQueue(input);
  assert.deepEqual(first, second);
  assert.ok(first.every((item) => !/\b(city|corporation)\b/i.test(`${item.id} ${item.title} ${item.whyItMatters}`)));
  assert.equal(first[0]?.riskLevel, 'critical');
  assert.ok(first.some((item) => item.targetSection === 'territory'));
  assert.ok(first.some((item) => item.targetSection === 'market'));
  assert.ok(first.some((item) => item.targetSection === 'house'));
});
