import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { loginIdentity } from '../cloudflare/src/auth-postgres.ts';
import { worldSnapshot } from '../cloudflare/src/world-postgres.ts';
import { purchasePrivatePlotAndConstruct, setBuildingOperatingPolicy, demolishBuilding } from '../cloudflare/src/real-estate-postgres.ts';
import { submitMarketOrder, cancelMarketOrder } from '../cloudflare/src/market-postgres.ts';
import { logAppError, listRecentAppErrors } from '../cloudflare/src/error-logger-postgres.ts';

const DATABASE_URL = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const TEST_EMAIL = 'vitalii.noga@gmail.com';
const TEST_PASSWORD = 'P@ssw0rdP@ssw0rd';

test('Live PostgreSQL Integration & E2E Suite', async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await client.end();
  });

  let testHumanId = '';
  let testToken = '';
  let createdBuildingId = '';

  await t.test('1. Authenticate test user with live credentials', async () => {
    await repo.query('DELETE FROM auth_login_attempts WHERE email = $1', [TEST_EMAIL]);

    const res = await loginIdentity(repo, {
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
      otp: '',
      validTotp: async () => false,
    });

    assert.equal(res.ok, true);
    assert.ok(res.token, 'Session token should be returned');
    assert.ok(res.human, 'Human record should be returned');
    testHumanId = res.human.id;
    testToken = res.token;
    assert.ok(testHumanId.startsWith('H-'), 'Human ID should follow H- prefix format');
  });

  await t.test('2. Retrieve authoritative world snapshot', async () => {
    assert.ok(testHumanId, 'User must be authenticated');
    const snapshot = await worldSnapshot(repo, testHumanId);

    assert.ok(snapshot.world, 'World state should exist');
    assert.ok(snapshot.human, 'Human state should exist');
    assert.equal(snapshot.human.id, testHumanId);
    assert.ok(snapshot.institutions, 'Institutions map should exist');
    assert.ok(snapshot.resources, 'Resource balances should exist');
    assert.ok(Array.isArray(snapshot.buildings), 'Buildings list should exist');
    assert.ok(snapshot.districtZoning, 'District zoning data should exist');
  });

  await t.test('3. Execute real estate construction for Bistro & Molecular Restaurant', async () => {
    assert.ok(testHumanId, 'User must be authenticated');
    
    await repo.query(`UPDATE account_balances SET balance = balance + 50000.00 WHERE owner_id = $1 AND currency = 'CREDIT'`, [testHumanId]);
    await repo.query(`INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1, 'material', 2000.0) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + 2000.0`, [testHumanId]);

    const correlationId = 'test-e2e-purchase-' + Date.now();
    const purchaseRes = await purchasePrivatePlotAndConstruct(repo, {
      ownerId: testHumanId,
      cityId: 'CITY-0084',
      buildingType: 'restaurant',
      name: 'E2E Molecular Bistro',
      correlationId,
    });

    assert.equal(purchaseRes.ok, true);
    assert.ok(purchaseRes.building, 'Building record should be created');
    createdBuildingId = purchaseRes.building.id;
    assert.ok(createdBuildingId.startsWith('BLD-'), 'Building ID should start with BLD-');
    assert.equal(purchaseRes.building.building_type, 'restaurant');
    assert.equal(purchaseRes.building.status, 'under_construction');
  });

  await t.test('4. Update operating policy and verify rate change timeline integration', async () => {
    assert.ok(createdBuildingId, 'Building must have been created');
    
    const policyRes = await setBuildingOperatingPolicy(repo, {
      humanId: testHumanId,
      buildingId: createdBuildingId,
      policy: 'high_output',
    });

    assert.equal(policyRes.ok, true);
    assert.equal(policyRes.policy, 'high_output');

    const history = await repo.query('SELECT * FROM resource_rate_history WHERE owner_id = $1 ORDER BY created_at DESC LIMIT 6', [testHumanId]);
    assert.ok(history.rows.length >= 6, 'Rate change history records should exist for all 6 resources');
  });

  await t.test('5. Market order lifecycle with real credit reservations', async () => {
    assert.ok(testHumanId, 'User must be authenticated');
    const correlationId = 'test-e2e-order-' + Date.now();

    const submitRes = await submitMarketOrder(repo, {
      humanId: testHumanId,
      product: 'material',
      side: 'buy',
      quantity: 10,
      limitPrice: 5.00,
      correlationId,
    });

    assert.equal(submitRes.ok, true);
    assert.ok(submitRes.order.id, 'Order ID must exist');
    const placedOrderId = submitRes.order.id;

    const cancelRes = await cancelMarketOrder(repo, {
      orderId: placedOrderId,
      humanId: testHumanId,
    });

    assert.equal(cancelRes.ok, true);
    assert.equal(cancelRes.orderId, placedOrderId);
  });

  await t.test('6. Record diagnostic error and verify app_error_logs audit', async () => {
    assert.ok(testHumanId, 'User must be authenticated');
    const testErrorMsg = 'E2E Diagnostic Test Exception - ' + Date.now();
    
    const logRes = await logAppError(repo, {
      humanId: testHumanId,
      source: 'client_flutter',
      endpoint: '/api/real-estate/purchase',
      statusCode: 500,
      errorCode: 'DIAGNOSTIC_TEST',
      errorMessage: testErrorMsg,
      contextData: { testRunner: 'postgres-live-e2e' },
    });

    assert.ok(logRes.id, 'Error log ID should be returned');

    const recent = await listRecentAppErrors(repo, { humanId: testHumanId, limit: 5 });
    const match = recent.find((r) => r.id === logRes.id);
    assert.ok(match, 'Logged error should be retrievable from app_error_logs');
    assert.equal(match.error_message, testErrorMsg);
  });

  await t.test('7. Cleanup test artifacts', async () => {
    if (createdBuildingId) {
      await demolishBuilding(repo, {
        humanId: testHumanId,
        buildingId: createdBuildingId,
      });
      await repo.query('DELETE FROM buildings WHERE id = $1', [createdBuildingId]);
    }
  });
});
