import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

test('corporations have a separate distress-to-liquidation lifecycle', () => {
  assert.match(scheduler, /current === 'distressed'/);
  assert.match(scheduler, /current === 'restructuring'/);
  assert.match(scheduler, /current === 'insolvent'/);
  assert.match(scheduler, /target === 'liquidation'/);
  assert.match(scheduler, /corporation_insolvency_proceedings SET status = 'LIQUIDATION'/);
  assert.match(scheduler, /kind = 'CORPORATION'/);
});

test('corporate liquidation releases House affiliations and discretionary commitments', () => {
  assert.match(scheduler, /UPDATE house_affiliations SET corporation_id = NULL/);
  assert.match(scheduler, /spending_class = 'DISCRETIONARY'/);
  assert.match(scheduler, /earth_project_house_affiliation_to_memberships/);
  assert.match(scheduler, /earth_transfer_dissolved_corporation_ip/);
  assert.match(schema, /corporation_insolvency_proceedings/);
});
