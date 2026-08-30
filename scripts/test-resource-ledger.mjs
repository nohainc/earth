import pg from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { mutateResourceBalance, getResourceLedgerHistory, getResourceDailyBreakdown } from '../cloudflare/src/resource-ledger-postgres.ts';
import { worldSnapshot } from '../cloudflare/src/world-postgres.ts';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });
await client.connect();

const repo = new PostgresRepository(client);
const testOwnerId = 'TEST-LEDGER-USER-' + Date.now();
const testAccountId = 'acc-' + testOwnerId;

try {
  console.log('=== TEST 1: Direct Resource Mutation & Audit Logging ===');
  const depositRes = await mutateResourceBalance(repo, {
    ownerId: testOwnerId,
    resource: 'material',
    delta: 250.0,
    reasonType: 'test_deposit',
    correlationId: `test-deposit-${testOwnerId}`,
    gameDay: 100,
  });
  console.log('Deposit Result:', depositRes);
  if (depositRes.balanceAfter !== 250.0) throw new Error('Expected balance 250.0');

  console.log('\n=== TEST 2: Idempotency with Correlation ID ===');
  const duplicateRes = await mutateResourceBalance(repo, {
    ownerId: testOwnerId,
    resource: 'material',
    delta: 250.0,
    reasonType: 'test_deposit',
    correlationId: `test-deposit-${testOwnerId}`,
    gameDay: 100,
  });
  console.log('Duplicate Result:', duplicateRes);
  if (!duplicateRes.alreadyProcessed) throw new Error('Expected alreadyProcessed to be true');

  console.log('\n=== TEST 3: Resource Deduction ===');
  const deductRes = await mutateResourceBalance(repo, {
    ownerId: testOwnerId,
    resource: 'material',
    delta: -75.5,
    reasonType: 'building_construction',
    reasonId: 'BLD-TEST-1',
    correlationId: `test-deduct-${testOwnerId}`,
    gameDay: 100,
  });
  console.log('Deduction Result:', deductRes);
  if (deductRes.balanceAfter !== 174.5) throw new Error('Expected balance 174.5');

  console.log('\n=== TEST 4: Overdraft Protection ===');
  let overdraftCaught = false;
  try {
    await mutateResourceBalance(repo, {
      ownerId: testOwnerId,
      resource: 'material',
      delta: -500.0,
      reasonType: 'illegal_overdraft',
      correlationId: `test-overdraft-${testOwnerId}`,
      gameDay: 100,
    });
  } catch (err) {
    overdraftCaught = true;
    console.log('Overdraft correctly rejected:', err.message);
  }
  if (!overdraftCaught) throw new Error('Expected overdraft to be rejected');

  console.log('\n=== TEST 5: Querying Ledger History ===');
  const history = await getResourceLedgerHistory(repo, testOwnerId);
  console.table(history.map(h => ({
    id: h.id,
    day: h.game_day,
    resource: h.resource,
    delta: h.delta,
    after: h.balance_after,
    reason: h.reason_type,
  })));
  if (history.length < 2) throw new Error('Expected at least 2 ledger rows');

  console.log('\n=== TEST 6: Querying Daily Breakdown ===');
  const breakdown = await getResourceDailyBreakdown(repo, testOwnerId);
  console.log('Material Breakdown:', breakdown.material);
  if (!breakdown.material || breakdown.material.length === 0) throw new Error('Expected breakdown for material');

  console.log('\n=== TEST 7: Settlement Profile Catch-Up Writes Ledger Records ===');
  await client.query(`
    INSERT INTO account_balances (account_id, owner_id, currency, balance)
    VALUES ($1, $2, 'CREDIT', 10000.0)
    ON CONFLICT (account_id) DO NOTHING
  `, [testAccountId, testOwnerId]);

  await client.query(`
    INSERT INTO humans (id, account_id, display_name, standing, legacy, life_status, age_years)
    VALUES ($1, $2, 'Ledger Tester', 100, 10, 'active', 30)
    ON CONFLICT (id) DO NOTHING
  `, [testOwnerId, testAccountId]);

  await client.query(`
    INSERT INTO buildings (
      id, name, building_type, owner_id, city_id, ownership_class,
      tier, status, condition, construction_progress,
      resource_output_type, resource_output_amount,
      upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
      daily_operating_credits, operating_policy, created_game_day
    ) VALUES (
      $1, 'Test Solar Array', 'solar_power_plant', $2, 'CITY-0084', 'private',
      1, 'active', 100.0, 100.0,
      'energy', 30.0,
      0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 'balanced', 1
    ) ON CONFLICT (id) DO NOTHING
  `, [`BLD-SOLAR-${testOwnerId}`, testOwnerId]);

  await client.query('SELECT * FROM earth_rebuild_settlement_profile($1)', [testOwnerId]);

  // Set last settled day to 5 days ago
  await client.query(`
    UPDATE daily_settlement_profiles
    SET last_settled_game_day = 14490
    WHERE owner_id = $1
  `, [testOwnerId]);

  // Catch-up to 14495
  const catchupRes = await client.query('SELECT * FROM earth_catchup_owner_settlement($1, 14495)', [testOwnerId]);
  console.log('Catch-up Result:', catchupRes.rows);

  const energyHistory = await getResourceLedgerHistory(repo, testOwnerId, { resource: 'energy' });
  console.log('Energy Ledger History after Catch-Up:');
  console.table(energyHistory.map(h => ({
    day: h.game_day,
    resource: h.resource,
    delta: h.delta,
    after: h.balance_after,
    reason: h.reason_type,
  })));
  if (energyHistory.length === 0) throw new Error('Expected energy ledger entry from catch-up');

  console.log('\n=== TEST 8: World Snapshot Includes Resource Ledger ===');
  const snap = await worldSnapshot(repo, testOwnerId);
  console.log('Snapshot resourceLedger count:', snap.resourceLedger?.length);
  if (!Array.isArray(snap.resourceLedger) || snap.resourceLedger.length === 0) {
    throw new Error('Expected resourceLedger in snapshot');
  }

  console.log('\n✅ ALL TESTS PASSED SUCCESSFULLY! Hybrid Ledger Architecture is fully verified.');

} finally {
  await client.end();
}
