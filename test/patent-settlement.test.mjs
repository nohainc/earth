import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('patent settlement grants completed patents and finalizes public-domain access', () => {
  const source = read('cloudflare/src/patent-settlement-postgres.ts');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(source, /earth_grant_completed_technology_patents/);
  assert.match(source, /earth_finalize_technology_public_domain/);
  assert.match(source, /patentsGranted/);
  assert.match(phases, /required\('patent_expirations'/);
  assert.match(scheduler, /settlePatentExpirations/);
});
