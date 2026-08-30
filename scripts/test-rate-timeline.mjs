import pg from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { getResourceRateHistory, recordRateChange, getResourceLedgerHistory } from '../cloudflare/src/resource-ledger-postgres.ts';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });
await client.connect();

const repo = new PostgresRepository(client);
const testOwnerId = 'TEST-TIMELINE-USER-' + Date.now();
const testAccountId = 'acc-' + testOwnerId;

try {
  console.log('=== TEST 1: User & Account Initialization ===');
  await client.query(`
    INSERT INTO account_balances (account_id, owner_id, currency, balance)
    VALUES ($1, $2, 'CREDIT', 100000.0)
  `, [testAccountId, testOwnerId]);

  await client.query(`
    INSERT INTO humans (id, account_id, display_name, standing, legacy, life_status, age_years)
    VALUES ($1, $2, 'Timeline Tester', 100, 10, 'active', 30)
  `, [testOwnerId, testAccountId]);

  console.log('User created successfully.');

  console.log('\n=== TEST 2: Initial Building Creation (Solar Plant +50 Energy/day at Day 100) ===');
  await client.query(`
    INSERT INTO buildings (
      id, name, building_type, owner_id, city_id, ownership_class,
      tier, status, condition, construction_progress,
      resource_output_type, resource_output_amount,
      upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
      daily_operating_credits, operating_policy, created_game_day
    ) VALUES (
      $1, 'Solar Plant 1', 'solar_power_plant', $2, 'CITY-0084', 'private',
      1, 'active', 100.0, 100.0,
      'energy', 50.0,
      0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 'balanced', 100
    )
  `, [`BLD-SOLAR-${testOwnerId}`, testOwnerId]);

  await client.query('SELECT * FROM earth_record_rate_change($1, $2, $3, 100, 0)', [
    testOwnerId, 'building_construction', `BLD-SOLAR-${testOwnerId}`
  ]);

  // Set last settled day to 100
  await client.query(`
    UPDATE daily_settlement_profiles
    SET last_settled_game_day = 100
    WHERE owner_id = $1
  `, [testOwnerId]);

  const ratesDay100 = await getResourceRateHistory(repo, testOwnerId);
  const energyRate100 = ratesDay100.find(r => r.resource === 'energy');
  console.log('Day 100 Energy Rate:', energyRate100);
  if (Number(energyRate100.net_daily_rate) !== 50.0) {
    throw new Error('Expected +50.0 net energy rate at Day 100');
  }

  console.log('\n=== TEST 3: Second Building Addition at Day 103 (Factory Consuming 20 Energy/day) ===');
  await client.query(`
    INSERT INTO buildings (
      id, name, building_type, owner_id, city_id, ownership_class,
      tier, status, condition, construction_progress,
      resource_output_type, resource_output_amount,
      upkeep_energy, upkeep_food, upkeep_materials, upkeep_components, upkeep_compute,
      daily_operating_credits, operating_policy, created_game_day
    ) VALUES (
      $1, 'Component Factory 1', 'components_foundry', $2, 'CITY-0084', 'private',
      1, 'active', 100.0, 100.0,
      'components', 10.0,
      20.0, 0.0, 5.0, 0.0, 1.0,
      0.0, 'balanced', 103
    )
  `, [`BLD-FACT-${testOwnerId}`, testOwnerId]);

  await client.query('SELECT * FROM earth_record_rate_change($1, $2, $3, 103, 0)', [
    testOwnerId, 'building_construction', `BLD-FACT-${testOwnerId}`
  ]);

  const ratesDay103 = await getResourceRateHistory(repo, testOwnerId);
  const energyRate103 = ratesDay103.find(r => r.resource === 'energy' && Number(r.game_day) === 103);
  console.log('Day 103 Energy Rate:', energyRate103);
  if (Number(energyRate103.net_daily_rate) !== 30.0) {
    throw new Error('Expected +30.0 net energy rate at Day 103 (50 inflow - 20 outflow)');
  }

  console.log('\n=== TEST 4: Timeline-Weighted Historical Catch-Up across Day 100 -> Day 108 ===');
  // Day 100 to 103 (3 days) @ 50/day = 150 energy
  // Day 103 to 108 (5 days) @ 30/day = 150 energy
  // Total expected energy = 300 energy!
  const catchupRes = await client.query('SELECT * FROM earth_catchup_owner_settlement($1, 108)', [testOwnerId]);
  console.log('Catch-up Result:', catchupRes.rows[0]);

  const energyBalance = await client.query('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = \'energy\'', [testOwnerId]);
  const finalEnergy = Number(energyBalance.rows[0]?.amount ?? 0);
  console.log('Final Energy Balance after 8 days of multi-rate catch-up:', finalEnergy);

  if (finalEnergy !== 300.0) {
    throw new Error(`Expected exactly 300.0 Energy, got ${finalEnergy}`);
  }

  console.log('\n=== TEST 5: Rate History Audit Query ===');
  const allRates = await getResourceRateHistory(repo, testOwnerId);
  console.table(allRates.map(r => ({
    day: r.game_day,
    created_at: r.created_at,
    event: r.trigger_event,
    entity: r.trigger_entity_id,
    resource: r.resource,
    inflow: r.gross_inflow,
    outflow: r.gross_outflow,
    net: r.net_daily_rate,
  })));

  console.log('\n=== TEST 6: Ledger Entries Generated by Timeline Catch-Up ===');
  const ledger = await getResourceLedgerHistory(repo, testOwnerId);
  console.table(ledger.map(l => ({
    day: l.game_day,
    resource: l.resource,
    delta: l.delta,
    balance_after: l.balance_after,
    reason: l.reason_type,
    created_at: l.created_at,
  })));

  console.log('\n ALL TESTS PASSED! Rate-Change Timeline and Multi-Segment Interval Catch-Up verified.');

} finally {
  await client.end();
}
