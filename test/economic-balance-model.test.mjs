import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/343_economic_balance_model.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');

test('economic balance model uses versioned reference values, not market prices', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS economic_reference_prices/);
  assert.match(migration, /reference_price_credit_units BIGINT/);
  assert.match(migration, /balance_version TEXT/);
  assert.match(migration, /CREATE OR REPLACE VIEW building_economic_balance_model/);
  assert.match(migration, /CREATE OR REPLACE VIEW building_tier_balance_flags/);
  assert.doesNotMatch(migration, /market_prices|market_candles|market_instrument_state/);
});

test('tier balance diagnostics detect unintended dominance without changing catalog data', () => {
  assert.match(migration, /unintended_dominance/);
  assert.match(migration, /higher_tier\.tier > lower_tier\.tier/);
  assert.match(migration, /daily_resource_input_value <= lower_tier\.daily_resource_input_value/);
  assert.match(migration, /expected_daily_revenue >= lower_tier\.expected_daily_revenue/);
  assert.match(schema, /building_tier_balance_flags/);
});

test('construction timing exposes one game-to-real-time conversion', () => {
  const time = fs.readFileSync('db/migrations/344_construction_time_economics.sql', 'utf8');
  assert.match(time, /building_construction_time_model/);
  assert.match(time, /construction_days \* 24 AS construction_game_hours/);
  assert.match(time, /construction_days \* 24 AS construction_real_minutes/);
  for (const durationClass of ['TINY_BASIC', 'ORDINARY_PRODUCTION', 'ADVANCED_HIGH_TIER', 'STRATEGIC_T5']) {
    assert.match(time, new RegExp(durationClass));
  }
});

test('operating cost diagnostics separate CREDIT expense and resource inputs', () => {
  const operating = fs.readFileSync('db/migrations/345_building_operating_cost_model.sql', 'utf8');
  assert.match(operating, /building_operating_cost_model/);
  assert.match(operating, /daily_credit_operating_cost/);
  assert.match(operating, /daily_resource_input_value/);
  assert.match(operating, /BASELINE_PROFITABLE/);
  assert.match(operating, /maintenance_model/);
  assert.match(operating, /included_in_credit_operating_expense/);
  assert.doesNotMatch(operating, /repair_(reserve|inventory)|condition_depreciation/i);
});

test('economic loop analysis exposes cycles and source/sink coverage', () => {
  const graph = fs.readFileSync('db/migrations/346_economic_loop_analysis.sql', 'utf8');
  assert.match(graph, /economic_recipe_edges/);
  assert.match(graph, /economic_recipe_cycles/);
  assert.match(graph, /value_multiplier > 1/);
  assert.match(graph, /economic_resource_flow_coverage/);
  assert.match(graph, /explicit_system_sources/);
  assert.match(graph, /explicit_system_sinks/);
});

test('research balance model links RP speed, building output impact, and payback', () => {
  const research = fs.readFileSync('db/migrations/347_research_building_balance_model.sql', 'utf8');
  for (const field of ['baseline_daily_research_capacity_units', 'expected_research_completion_days', 'expected_real_completion_hours', 'expected_daily_impact_value', 'economic_payback_game_days', 'economic_payback_real_hours', 'prerequisite_count']) {
    assert.match(research, new RegExp(field));
  }
  assert.match(research, /PRODUCTION_OUTPUT/);
  assert.match(research, /technology_effects/);
  assert.match(research, /economic_reference_prices/);
});

test('balance model exposes the required diagnostic metrics', () => {
  for (const field of [
    'construction_reference_value', 'daily_resource_input_value',
    'daily_credit_operating_cost', 'total_daily_cost',
    'daily_output_reference_value', 'expected_daily_revenue',
    'gross_margin', 'operating_margin', 'payback_game_days',
    'payback_real_hours', 'return_on_capital_per_day',
    'output_per_slot', 'profit_per_slot',
  ]) assert.match(migration, new RegExp(field));
  assert.match(schema, /economic_reference_prices/);
});
