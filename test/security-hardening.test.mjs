import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('security gate audits runtime dependencies and hardens Worker boundaries', () => {
  const index = fs.readFileSync('cloudflare/src/index.ts', 'utf8');
  const audit = fs.readFileSync('scripts/verify-dependency-security.mjs', 'utf8');
  const policy = fs.readFileSync('docs/SECURITY_DEPENDENCY_POLICY.md', 'utf8');
  assert.match(index, /corsOriginFor/);
  assert.match(index, /status: 403/);
  assert.doesNotMatch(index, /Access-Control-Allow-Origin': origin \?\? '\*'/);
  for (const header of ['X-Content-Type-Options', 'X-Frame-Options', 'Referrer-Policy', 'Permissions-Policy']) assert.match(index, new RegExp(header));
  assert.match(audit, /npm.*audit/);
  assert.match(audit, /--omit=dev/);
  assert.match(audit, /critical/);
  assert.match(policy, /block CI and deployment/);
});
