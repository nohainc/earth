import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { featureConfig, featureDisabledResponse, featureEnabled } from '../cloudflare/src/feature-config.ts';

test('feature configuration has one centralized registry with safe defaults', () => {
  const config = featureConfig({});
  assert.equal(config.spotMarket, true);
  assert.equal(config.bankDeposits, true);
  assert.equal(config.forcedLiquidation, false);
  assert.equal(Object.keys(config).length, 10);
});

test('feature flags parse explicit deployment values consistently', () => {
  const env = { FEATURE_FUTURES: 'false', FEATURE_COMMUNITIES: '0', FEATURE_SPOT_MARKET: 'ON', FEATURE_MORTALITY: 'yes' };
  assert.equal(featureEnabled(env, 'futures'), false);
  assert.equal(featureEnabled(env, 'communities'), false);
  assert.equal(featureEnabled(env, 'spotMarket'), true);
  assert.equal(featureEnabled(env, 'mortality'), true);
  assert.equal(featureDisabledResponse('futures').status, 404);
});

test('progressive activation stage caps advanced features in a fixed order', () => {
  const baseline = featureConfig({ EARTH_FEATURE_ACTIVATION_STAGE: 'baseline' });
  assert.equal(baseline.spotMarket, true);
  assert.equal(baseline.bankDeposits, true);
  assert.equal(baseline.bankLoans, false);
  assert.equal(baseline.mortality, false);
  assert.equal(baseline.futures, false);

  const patents = featureConfig({ EARTH_FEATURE_ACTIVATION_STAGE: 'patents' });
  assert.equal(patents.bankLoans, true);
  assert.equal(patents.mortality, true);
  assert.equal(patents.patents, true);
  assert.equal(patents.technologyLicenses, false);
  assert.equal(patents.futures, false);

  const full = featureConfig({ EARTH_FEATURE_ACTIVATION_STAGE: 'all' });
  assert.equal(full.futures, true);
});

test('server mutation surfaces consult the central registry', () => {
  const read = (path) => fs.readFileSync(path, 'utf8');
  assert.match(read('cloudflare/src/index.ts'), /featureEnabled\(env, 'futures'\)/);
  assert.match(read('cloudflare/src/market-api.ts'), /featureEnabled\(env, 'spotMarket'\)/);
  assert.match(read('cloudflare/src/community-routes.ts'), /featureEnabled\(env, 'communities'\)/);
  assert.match(read('cloudflare/src/finance-routes.ts'), /featureEnabled\(env, 'bankDeposits'\)/);
  assert.match(read('cloudflare/src/scheduler.ts'), /features\.spotMarket/);
  assert.match(read('cloudflare/src/market-scheduler.ts'), /features\?\.futures/);
});
