import test from 'node:test';
import assert from 'node:assert/strict';
import { marketFeeRate } from '../cloudflare/src/market-rules.ts';

function repository({ earth = '0.02', city = null, corporation = null } = {}) {
  return {
    async query(sql) {
      if (sql.includes("EARTH.MARKET.TRANSACTION_TAX_RATE")) {
        return { rows: [{ rate_bps: Math.round(Number(earth) * 10000).toString() }] };
      }
      return { rows: [{ corporation_sales_rate: corporation?.salesTaxBps?.toString() ?? null }] };
    },
  };
}

test('Corporation constitutional sales tax overrides the Earth market fee', async () => {
  const rate = await marketFeeRate(repository({ corporation: { salesTaxBps: 300 } }), 'H-001');
  assert.equal(rate, '0.03');
});

test('corporation sales tax is used when the House is affiliated', async () => {
  const rate = await marketFeeRate(repository({ corporation: { salesTaxBps: 450 } }), 'H-002');
  assert.equal(rate, '0.045');
});

test('Earth market fee remains the fallback for unaffiliated humans', async () => {
  const rate = await marketFeeRate(repository(), 'H-003');
  assert.equal(rate, '0.02');
});
