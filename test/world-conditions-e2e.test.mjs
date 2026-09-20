import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  applyConditionStack,
  conditionIsEffective,
  WORLD_CONDITION_EFFECT_REGISTRY,
  WORLD_CONDITION_SCOPES,
} from '../cloudflare/src/world-conditions.ts';
import { listWorldConditions } from '../cloudflare/src/world-conditions-postgres.ts';

const conditions = [
  {
    id: 'COND-EARTH-1',
    condition_code: 'EARTH-SOLAR',
    title: 'Solar abundance',
    description: 'Earth-wide energy output modifier',
    source_type: 'SYSTEM_EVENT',
    source_id: 'EVENT-1',
    scope_type: 'EARTH',
    scope_id: null,
    severity: 'INFO',
    definition_version: '2',
    effective_from_game_day: 1,
    effective_to_game_day: null,
    rules_version: 'world-conditions-v1',
    effects: [
      { type: 'SUPPLY_MULTIPLIER', target: 'ENERGY', modifierBps: 1250, order: 1 },
      { type: 'DEMAND_MULTIPLIER', target: 'ENERGY', modifierBps: 100, order: 2 },
    ],
  },
  {
    id: 'COND-CORP-1',
    condition_code: 'CORP-MAINTENANCE',
    title: 'Corporation maintenance pressure',
    description: 'Corporation-specific capacity pressure',
    source_type: 'INITIATIVE',
    source_id: 'INIT-1',
    scope_type: 'CORPORATION',
    scope_id: 'CORP-1',
    severity: 'WATCH',
    definition_version: '2',
    effective_from_game_day: 8,
    effective_to_game_day: 12,
    rules_version: 'world-conditions-v1',
    effects: [
      { type: 'CAPACITY_MULTIPLIER', target: 'HEALTH', modifierBps: -500, order: 1 },
    ],
  },
  {
    id: 'COND-CORP-2',
    condition_code: 'OTHER-CORP',
    title: 'Other corporation condition',
    description: 'Must not expose to Corp 1 members',
    source_type: 'INITIATIVE',
    source_id: 'INIT-2',
    scope_type: 'CORPORATION',
    scope_id: 'CORP-2',
    severity: 'INFO',
    definition_version: '2',
    effective_from_game_day: 1,
    effective_to_game_day: null,
    rules_version: 'world-conditions-v1',
    effects: [],
  },
];

function repositoryFor(day) {
  return {
    async query(sql, params = []) {
      if (sql.includes('FROM house_affiliations')) {
        return { rows: [{ id: 'CORP-1', name: 'Nova' }] };
      }
      if (sql.includes('FROM world_conditions wc')) {
        return {
          rows: conditions.filter((row) =>
            row.effective_from_game_day <= day &&
            (row.effective_to_game_day == null || row.effective_to_game_day >= day)),
        };
      }
      throw new Error(`Unexpected query in world-condition integration fixture: ${sql}`);
    },
  };
}

test('Earth and Corporation conditions resolve applicability without Territory exposure', async () => {
  const snapshot = await listWorldConditions(repositoryFor(10), 10, 'HOUSE-1');
  assert.equal(snapshot.status, 'AVAILABLE');
  assert.equal(snapshot.worldState, 'ACTIVE');
  assert.deepEqual(WORLD_CONDITION_SCOPES, ['EARTH', 'CORPORATION']);
  assert.equal(snapshot.globalConditionCount, 3);
  assert.equal(snapshot.viewerApplicableConditionCount, 2);

  const earth = snapshot.conditions.find((condition) => condition.id === 'COND-EARTH-1');
  const corporation = snapshot.conditions.find((condition) => condition.id === 'COND-CORP-1');
  const otherCorporation = snapshot.conditions.find((condition) => condition.id === 'COND-CORP-2');
  assert.equal(earth?.appliesToViewer, true);
  assert.equal(earth?.exposureReason, 'EARTHWIDE');
  assert.equal(corporation?.appliesToViewer, true);
  assert.equal(corporation?.exposureReason, 'CORPORATION_AFFILIATION');
  assert.equal(otherCorporation?.appliesToViewer, false);
  assert.equal(otherCorporation?.exposureReason, 'NOT_APPLICABLE');
  assert.ok(snapshot.conditions.every((condition) => condition.scope.type !== 'TERRITORY'));
});

test('multiple effects preserve order and use exact sequential BPS arithmetic', async () => {
  const snapshot = await listWorldConditions(repositoryFor(10), 10, 'HOUSE-1');
  const effects = snapshot.conditions.find((condition) => condition.id === 'COND-EARTH-1').effects;
  assert.deepEqual(effects.map((effect) => effect.type), ['SUPPLY_MULTIPLIER', 'DEMAND_MULTIPLIER']);
  assert.equal(applyConditionStack(1000n, effects.map((effect) => effect.modifierBps)), 1136n);
  assert.equal(applyConditionStack(1000n, [100, 1250]), 1136n);
});

test('expired conditions disappear from the authoritative snapshot', async () => {
  const snapshot = await listWorldConditions(repositoryFor(13), 13, 'HOUSE-1');
  assert.equal(snapshot.conditions.some((condition) => condition.id === 'COND-CORP-1'), false);
  assert.equal(conditionIsEffective({ effectiveFromGameDay: 8, effectiveToGameDay: 12 }, 13), false);
});

test('the same registered effects are consumed by quote and settlement paths', () => {
  const quote = fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8');
  const settlement = fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8');
  const serviceSettlement = fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8');
  assert.match(quote, /JOIN world_condition_effects/);
  assert.match(quote, /applyConditionStack/);
  assert.match(settlement, /JOIN world_condition_effects/);
  assert.match(settlement, /applyConditionStack/);
  assert.match(serviceSettlement, /JOIN world_condition_effects/);
  assert.match(serviceSettlement, /applyConditionStack/);
  assert.match(quote, /conditionModifiers/);
  assert.match(settlement, /adjustedInputUnits/);
});

test('every registered effect has a concrete authoritative runtime consumer', () => {
  const consumerSources = new Map([
    ['building-settlement-v2', fs.readFileSync('cloudflare/src/building-settlement-v2.ts', 'utf8')],
    ['service-settlement', fs.readFileSync('cloudflare/src/service-settlement-postgres.ts', 'utf8')],
    ['territory-capacity', fs.readFileSync('cloudflare/src/territory-capacity-postgres.ts', 'utf8')],
  ]);
  for (const [effect, metadata] of Object.entries(WORLD_CONDITION_EFFECT_REGISTRY)) {
    const consumers = metadata.consumer.split('+');
    assert.ok(consumers.length > 0, `${effect} must declare a consumer`);
    for (const consumer of consumers) {
      const sourceName = consumer.split('.')[0];
      const source = consumerSources.get(sourceName);
      assert.ok(source, `${effect} references missing consumer source ${sourceName}`);
      assert.match(source, new RegExp(effect), `${effect} is not implemented by ${sourceName}`);
      assert.match(source, /applyConditionStack/, `${sourceName} must apply fixed-point stacking`);
    }
  }
});

test('unavailable is explicit and stale is not presented as a valid state', () => {
  const route = fs.readFileSync('cloudflare/src/read-model-routes.ts', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/world/world_conditions_panel.dart', 'utf8');
  assert.match(route, /PostgreSQL persistence is unavailable/);
  assert.match(route, /status: 503/);
  assert.match(panel, /CONDITIONS UNAVAILABLE/);
  assert.match(panel, /snapshot could not be verified/);
  assert.doesNotMatch(panel, /STALE SNAPSHOT|stale/);
});
