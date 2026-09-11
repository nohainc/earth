import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/221_tax_rule_effective_days.sql', import.meta.url), 'utf8');

test('tax rules are immutable versions selected by effective game day', () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS tax_rule_versions/);
  for (const field of ['effective_from_game_day', 'effective_to_game_day', 'rate_bps', 'tax_base_definition', 'beneficiary_economic_id']) assert.match(migration, new RegExp(field));
  assert.match(migration, /earth_get_tax_rule_version/);
  assert.match(migration, /effective_from_game_day <= p_game_day/);
  assert.match(migration, /Historical tax rule versions are immutable/);
  assert.match(migration, /external_market_trade/);
});
