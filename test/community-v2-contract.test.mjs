import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const contract = fs.readFileSync('docs/architecture/community-v2-contract.md', 'utf8');
const routes = fs.readFileSync('cloudflare/src/community-routes.ts', 'utf8');
const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');
const features = fs.readFileSync('cloudflare/src/feature-config.ts', 'utf8');

test('Community V2 freezes House membership and non-economic boundaries', () => {
  assert.match(contract, /persistent membership principal is a \*\*House\*\*/);
  assert.match(contract, /OWNER.*MODERATOR.*MEMBER/s);
  assert.match(contract, /PUBLIC.*PRIVATE/s);
  assert.match(contract, /OPEN.*REQUEST/s);
  assert.match(contract, /has no[\s\S]*?treasury, CREDIT account, resource inventory/);
  assert.match(contract, /contributions are intentionally not part of V2/i);
});

test('Communities use the V2 feature and schema contract', () => {
  assert.match(features, /communities: true/);
  assert.doesNotMatch(routes, /contributions/);
  assert.doesNotMatch(lifecycle, /community_members/);
});
