import test from 'node:test';
import assert from 'node:assert/strict';
import { allocateCommonsDividend } from '../cloudflare/src/commons-dividends-postgres.ts';

test('commons dividend allocation conserves every unit and makes remainder explicit', () => {
  for (const total of [0n, 1n, 2n, 17n, 1000003n]) {
    for (const holders of [
      [{ houseId: 'B', slotQuantity: 1n }, { houseId: 'A', slotQuantity: 2n }],
      [{ houseId: 'A', slotQuantity: 1n }, { houseId: 'B', slotQuantity: 1n }, { houseId: 'C', slotQuantity: 3n }],
    ]) {
      const result = allocateCommonsDividend(total, holders);
      assert.equal(result.reduce((sum, row) => sum + row.amountUnits, 0n), total);
      assert.ok(result.every((row) => row.amountUnits >= 0n && row.remainderUnits >= 0n));
      assert.ok(result.filter((row) => row.remainderUnits > 0n).length <= 1);
    }
  }
});

test('commons allocation ordering is stable regardless of database row order', () => {
  const first = allocateCommonsDividend(11n, [{ houseId: 'Z', slotQuantity: 1n }, { houseId: 'A', slotQuantity: 1n }]);
  const second = allocateCommonsDividend(11n, [{ houseId: 'A', slotQuantity: 1n }, { houseId: 'Z', slotQuantity: 1n }]);
  assert.deepEqual(first, second);
});
