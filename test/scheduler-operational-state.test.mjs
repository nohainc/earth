import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('health exposes resumable settlement operational state', () => {
  const source = fs.readFileSync('cloudflare/src/health.ts', 'utf8');
  for (const field of ['current_phase', 'lease_owner', 'lease_heartbeat_at', 'phase_completed', 'phase_total', 'failed_runs', 'retry_count']) {
    assert.match(source, new RegExp(field));
  }
  for (const field of ['currentPhase', 'leaseOwner', 'phaseProgress', 'failedRuns', 'retryCount']) {
    assert.match(source, new RegExp(field));
  }
});

test('scheduler keeps completion and retry work behind database leases', () => {
  const source = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  assert.match(source, /earth_claim_settlement_day/);
  assert.match(source, /earth_heartbeat_settlement_day/);
  assert.match(source, /earth_complete_settlement_day/);
  assert.match(source, /earth_fail_settlement_day/);
  assert.match(source, /Settlement day lease lost/);
});
