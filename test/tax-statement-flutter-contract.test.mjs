import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Flutter Finance transport exposes the authoritative tax statement', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_personal_finance.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/finance/personal_finance_panel.dart', 'utf8');
  assert.match(api, /taxStatement/);
  assert.match(api, /finance\/tax-statement/);
  assert.match(panel, /tax/i);
  assert.match(panel, /arrear|obligation|rule/i);
});
