import test from 'node:test';
import assert from 'node:assert/strict';
import { validateWorldAdvanceMinutes } from '../cloudflare/src/scheduler-rules.ts';

test('world advancement rejects unbounded or invalid tick sizes', () => {
  assert.throws(() => validateWorldAdvanceMinutes(0), /between 1 and 1,440/);
  assert.throws(() => validateWorldAdvanceMinutes(1441), /between 1 and 1,440/);
  assert.throws(() => validateWorldAdvanceMinutes(1.5), /between 1 and 1,440/);
  assert.doesNotThrow(() => validateWorldAdvanceMinutes(5));
});
