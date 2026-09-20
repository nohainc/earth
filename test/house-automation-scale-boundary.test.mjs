import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { parseCreditAmount } from '../cloudflare/src/money.ts';
import {
  displayPriceToUnits,
  displayQuantityToUnits,
} from '../cloudflare/src/market-units.ts';

test('house automation converts player-facing decimals exactly once at the server boundary', () => {
  assert.equal(parseCreditAmount('100').toString(), '10000');
  assert.equal(displayQuantityToUnits('10').toString(), '10000000');
  assert.equal(displayPriceToUnits('2.50').toString(), '250');
});

test('house automation contracts do not expose atomic-unit request fields', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_house.dart', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/house-routes.ts', 'utf8');
  const persistence = fs.readFileSync('cloudflare/src/house-policy-postgres.ts', 'utf8');
  const execution = fs.readFileSync('cloudflare/src/house-policy-execution.ts', 'utf8');
  const migration = fs.readFileSync('db/migrations/147_house_automation_versions.sql', 'utf8');
  const semanticsMigration = fs.readFileSync('db/migrations/148_house_automation_resource_policy_semantics.sql', 'utf8');
  const auditMigration = fs.readFileSync('db/migrations/150_house_automation_execution_audit.sql', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/house/house_policy_panel.dart', 'utf8');

  for (const source of [api, routes]) {
    assert.match(source, /dailySpendCap/);
    assert.match(source, /minimumReserve/);
    assert.match(source, /sellAbove/);
    assert.match(source, /maxInputPrice/);
    assert.match(source, /minSalePrice/);
    assert.match(source, /maxBuyQuantity/);
    assert.match(source, /maxSellQuantity/);
    assert.doesNotMatch(source, /dailySpendCapUnits|reserveFloorUnits|maxInputPriceUnits|minSalePriceUnits|procurementQuantityUnits/);
  }

  assert.match(persistence, /parseCreditAmount\(/);
  assert.match(persistence, /decimalMap\(/);
  assert.match(persistence, /displayMap\(/);
  assert.match(persistence, /currentInventory/);
  assert.match(persistence, /referenceMarketPrices/);
  assert.match(persistence, /openAutomatedOrders/);
  assert.match(persistence, /recentExecutionSummaries/);
  assert.match(persistence, /compileHousePolicy\(/);
  assert.match(persistence, /maximumCreditReservation/);
  assert.match(persistence, /spendCapConsumption/);
  assert.match(persistence, /current: current\[0\] \? displayPolicy/);
  assert.match(persistence, /scheduled: scheduled\[0\] \? displayPolicy/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS house_automation_versions/);
  assert.match(semanticsMigration, /minimum_reserve_units/);
  assert.match(semanticsMigration, /sell_above_units/);
  assert.match(semanticsMigration, /max_buy_quantity_units/);
  assert.match(semanticsMigration, /max_sell_quantity_units/);
  assert.match(fs.readFileSync('db/migrations/149_house_automation_enabled_state.sql', 'utf8'), /enabled BOOLEAN NOT NULL DEFAULT TRUE/);
  assert.match(execution, /FROM house_automation_versions/);
  assert.match(execution, /enabled = TRUE/);
  assert.doesNotMatch(execution, /DISTINCT ON \(house_id\)/);
  assert.match(execution, /row_number\(\) OVER \(PARTITION BY house_id/);
  assert.doesNotMatch(persistence, /operatingMode: row\.operating_mode/);
  assert.doesNotMatch(panel, /_operatingMode/);
  assert.match(fs.readFileSync('db/migrations/147_house_automation_versions.sql', 'utf8'), /presets are not an execution input/);
  for (const status of ['NO_ACTION', 'ORDER_PLACED', 'PARTIALLY_FILLED', 'FILLED', 'EXPIRED', 'SKIPPED', 'FAILED']) {
    assert.match(auditMigration, new RegExp(status));
  }
  assert.match(auditMigration, /market_order_id/);
  assert.match(auditMigration, /policy_execution_daily_summaries/);
  assert.match(execution, /refreshAndSummarizeExecution/);
  assert.match(execution, /ORDER_SUBMISSION_FAILED/);
  assert.match(panel, /PARTIALLY FILLED/);
  assert.match(panel, /NO ACTION/);
  assert.match(routes, /\/api\/house\/automation\/preview/);
  assert.doesNotMatch(panel, /day \+ 1/);
});
