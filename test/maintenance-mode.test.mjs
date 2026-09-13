import test from 'node:test';
import assert from 'node:assert/strict';
import { maintenanceModeEnabled, maintenanceResponse, schedulerEnabled } from '../cloudflare/src/maintenance.ts';

test('maintenance mode is opt-in and rejects non-liveness traffic', async () => {
  assert.equal(maintenanceModeEnabled({ EARTH_MAINTENANCE_MODE: 'true' }), true);
  assert.equal(maintenanceModeEnabled({ EARTH_MAINTENANCE_MODE: 'false' }), false);
  assert.equal(schedulerEnabled({ EARTH_SCHEDULER_ENABLED: 'false' }), false);
  assert.equal(schedulerEnabled({ EARTH_SCHEDULER_ENABLED: 'true' }), true);
  const response = maintenanceResponse();
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, 'MAINTENANCE_MODE');
  assert.equal(response.headers.get('Retry-After'), '60');
});
