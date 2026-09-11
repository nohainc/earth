import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

test('Cities use a recoverable fiscal state machine', () => {
  assert.match(scheduler, /target = city/);
  assert.match(scheduler, /'fiscal_stress'/);
  assert.match(scheduler, /'receivership'/);
  assert.match(scheduler, /'recovery'/);
  assert.match(scheduler, /kind = 'CORPORATION'/);
  assert.match(scheduler, /RECEIVERSHIP_RECEIVER/);
  assert.match(scheduler, /city_fiscal_proceedings/);
});

test('City fiscal schema includes receivership and recovery states', () => {
  assert.match(schema, /status TEXT NOT NULL CHECK \(status IN \('active','distressed','fiscal_stress','receivership','recovery'/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS city_fiscal_proceedings/);
  assert.match(schema, /'FISCAL_STRESS','RECEIVERSHIP','RECOVERY','ACTIVE','FAILED'/);
});
