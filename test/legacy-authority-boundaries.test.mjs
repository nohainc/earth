import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('obsolete continuous and V1 settlement implementations are absent', () => {
  for (const path of [
    'cloudflare/src/engines/simulation-orchestrator.ts',
    'cloudflare/src/engines/time-engine.ts',
    'cloudflare/src/engines/market-engine.ts',
    'cloudflare/src/building-settlement-engine.ts',
  ]) assert.equal(fs.existsSync(path), false, `${path} must remain deleted`);
  assert.match(read('cloudflare/src/market-scheduler.ts'), /settleMarketBatch/);
  assert.match(read('cloudflare/src/scheduler.ts'), /processDueMarketBatches/);
});

test('legacy accounting remains explicitly transitional rather than silently authoritative', () => {
  const baseline = read('docs/ARCHITECTURE_BASELINE.md');
  assert.match(baseline, /Economy V2 is still in migration\/shadow-reconciliation mode/);
  assert.match(baseline, /account_balances.*resource_balances.*ledger_entries/);
  assert.match(baseline, /obsolete continuous simulation orchestrator/);
});
