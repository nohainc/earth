import test from 'node:test';
import assert from 'node:assert/strict';
import { postgresClient } from './postgres-connection.mjs';

const connectionString = process.env.DATABASE_URL;

test('fresh PostgreSQL certification includes the Community V2 migration', { skip: !connectionString }, async () => {
  const client = postgresClient(connectionString, 'earth-community-v2-certification');
  await client.connect();
  try {
    const migration = await client.query("SELECT version, name FROM earth_schema_migrations WHERE version = 2");
    assert.equal(migration.rowCount, 1);
    assert.equal(migration.rows[0].name, '002_communities_v2.sql');

    const tables = await client.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('communities', 'community_memberships', 'community_membership_requests')
      ORDER BY table_name
    `);
    assert.deepEqual(tables.rows.map((row) => row.table_name), [
      'communities',
      'community_membership_requests',
      'community_memberships',
    ]);

    const constraints = await client.query(`
      SELECT tc.table_name, tc.constraint_name
      FROM information_schema.table_constraints tc
      WHERE tc.table_schema = 'public'
        AND tc.table_name IN ('communities', 'community_memberships', 'community_membership_requests')
        AND tc.constraint_type = 'CHECK'
    `);
    assert.ok(constraints.rows.some((row) => row.table_name === 'communities'));
    assert.ok(constraints.rows.some((row) => row.table_name === 'community_memberships'));
    assert.ok(constraints.rows.some((row) => row.table_name === 'community_membership_requests'));

    const economicObjects = await client.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('community_contributions', 'community_balances', 'community_resources', 'community_economic_accounts')
    `);
    assert.equal(economicObjects.rowCount, 0);
  } finally {
    await client.end();
  }
});
