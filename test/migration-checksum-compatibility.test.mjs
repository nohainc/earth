import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('migration runner only grandfather-approved historical migration drift', () => {
  const source = fs.readFileSync('scripts/migrate-postgres.mjs', 'utf8');
  assert.match(source, /approvedHistoricalChecksums/);
  assert.match(source, /e2cfdb721f8367ce49a56c6679cdea63ce384b95ecf866923c499d804c0102a6/);
  assert.match(source, /7257e134835aced183eb02afbb82780c29170cbb0fded680f908e88001e2de57/);
  assert.match(source, /c4946ae53bbd774353c16533b2f27b6077ed3f5c8f91d22d23201b55fa14c857/);
  assert.match(source, /e864fc948fd6b9f07bf9b08c659a6262a656f0d727e62fbb58394929ef8a4822/);
  assert.match(source, /fe632055188742f32218deede17e7b116d292a9f281b9daa2af99845d0bfa299/);
  assert.match(source, /1558fff4f4d692778f8536d754128718aa585d4d0ab4f5d1c2e5aff26448aa33/);
  assert.match(source, /2d67d9995d01017155532227ee03db34b04aadc48f4e75ce3b3220f370d94a34/);
  assert.match(source, /preserving the applied migration record/);
  assert.match(source, /appliedName !== name/);
});
