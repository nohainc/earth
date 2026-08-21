import test from 'node:test';
import assert from 'node:assert/strict';
import { marketFeeRate } from '../cloudflare/src/market-rules.ts';

function repository({ earth = '0.02', city = null, corporation = null } = {}) {
  return {
    async query(sql) {
      if (sql.includes("scope = 'global'") && sql.includes("category = 'market'")) {
        return { rows: [{ rate: earth }] };
      }
      return { rows: [{ city_rules: city, corporation_rules: corporation }] };
    },
  };
}

test('city sales tax overrides corporation and Earth market fees', async () => {
  const rate = await marketFeeRate(repository({ city: { salesTaxBps: 700 }, corporation: { salesTaxBps: 300 } }), 'H-001');
  assert.equal(rate, '0.07');
});

test('corporation sales tax is used when the city has no override', async () => {
  const rate = await marketFeeRate(repository({ corporation: { salesTaxBps: 450 } }), 'H-002');
  assert.equal(rate, '0.045');
});

test('Earth market fee remains the fallback for unaffiliated humans', async () => {
  const rate = await marketFeeRate(repository(), 'H-003');
  assert.equal(rate, '0.02');
});
