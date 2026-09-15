import test from 'node:test';
import assert from 'node:assert/strict';
import { ENTRY_SUPPORT_RULES, evaluateEntrySupportEligibility } from '../cloudflare/src/catch-up.ts';

const base = { onboardingStatus: 'ACTIVE', currentGameDay: 100, entryGameDay: 100, eligibleUntilGameDay: 130, buildingCount: 0, marketOrderCount: 0, affiliationCount: 0, supportStatus: 'ELIGIBLE' };

test('entry support is bounded and resource-only', () => {
  assert.equal(ENTRY_SUPPORT_RULES.creditUnits, 0);
  assert.equal(Object.keys(ENTRY_SUPPORT_RULES.resourceBundleDisplayUnits).length, 3);
  assert.equal(evaluateEntrySupportEligibility(base).eligible, true);
  assert.equal(evaluateEntrySupportEligibility({ ...base, buildingCount: 1 }).eligible, false);
  assert.equal(evaluateEntrySupportEligibility({ ...base, supportStatus: 'CLAIMED' }).eligible, false);
  assert.equal(evaluateEntrySupportEligibility({ ...base, entryGameDay: 69 }).eligible, false);
});

test('mature technology is never granted by entry support', () => {
  assert.equal('frontierTechnologyFree' in { frontierTechnologyFree: false }, true);
});

test('getHouseEntrySupport executes query facts and opportunities with mock repository', async () => {
  const { getHouseEntrySupport } = await import('../cloudflare/src/catch-up-postgres.ts');
  const queries = [];
  const mockRepo = {
    async query(sql, params) {
      queries.push({ sql, params });
      if (sql.includes('FROM world_state')) return { rows: [{ game_day: '10' }] };
      if (sql.includes('FROM house_onboarding_progress')) return { rows: [{ status: 'ACTIVE' }] };
      if (sql.includes('FROM houses')) return { rows: [{ created_game_day: '1' }] };
      if (sql.includes('FROM buildings')) return { rows: [{ count: '0' }] };
      if (sql.includes('FROM market_orders') && !sql.includes('market_instruments')) return { rows: [{ count: '0' }] };
      if (sql.includes('FROM organization_memberships') && !sql.includes('organizations o')) return { rows: [{ count: '0' }] };
      if (sql.includes('FROM house_entry_support')) return { rows: [{ house_id: 'H-1', status: 'ELIGIBLE', entry_game_day: '10', eligible_until_game_day: '40', claimed_game_day: null, correlation_id: null }] };
      if (sql.includes('FROM territories t')) return { rows: [] };
      if (sql.includes('FROM organizations o')) return { rows: [{ id: 'ORG-1', name: 'Alpha Org', archetype: 'COMMERCIAL', join_policy: 'OPEN', member_count: '2' }] };
      if (sql.includes('FROM market_instruments i')) return { rows: [] };
      return { rows: [] };
    }
  };

  const result = await getHouseEntrySupport(mockRepo, 'H-1');
  assert.equal(result.ok, true);
  assert.equal(result.opportunities.organizations.length, 1);
  assert.equal(result.opportunities.organizations[0].name, 'Alpha Org');

  // Verify the organization query doesn't attempt casting the member_count alias in ORDER BY
  const orgQuery = queries.find(q => q.sql.includes('FROM organizations o'));
  assert.ok(orgQuery);
  assert.ok(!orgQuery.sql.includes('member_count::INTEGER'));
  assert.ok(orgQuery.sql.includes('ORDER BY COUNT(m.id) ASC'));
});
