import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('world health reports actionable production metrics', () => {
  const source = fs.readFileSync('cloudflare/src/health.ts', 'utf8');
  for (const metric of ['current_game_day', 'last_completed_game_day', 'backlog_game_days', 'current_phase', 'lease_owner', 'failed_runs', 'retry_count', 'active_buildings', 'inactive_buildings', 'market_orders_processed', 'pg_stat_activity', 'slow_queries', 'api_errors', 'worker_errors']) {
    assert.match(source, new RegExp(metric));
  }
  assert.match(source, /worldHealth/);
});

test('optional PostgreSQL observability extensions cannot make health fail', () => {
  const source = fs.readFileSync('cloudflare/src/health.ts', 'utf8');
  assert.match(source, /pg_stat_statements[\s\S]*\.catch/);
  assert.match(source, /app_error_logs[\s\S]*\.catch/);
});
