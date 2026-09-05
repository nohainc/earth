import test from 'node:test';
import assert from 'node:assert/strict';
import { extractToken, extractTokens } from '../cloudflare/src/auth-token.ts';

test('explicit bearer token takes precedence over a stale session cookie', () => {
  const request = new Request('http://localhost/api/finance/personal', {
    headers: {
      Cookie: 'earth_session=stale-cookie-token',
      Authorization: 'Bearer fresh-bearer-token',
    },
  });

  assert.equal(extractToken(request), 'fresh-bearer-token');
  assert.deepEqual(extractTokens(request), ['fresh-bearer-token', 'stale-cookie-token']);
});

test('cookie authentication remains supported when no bearer token is sent', () => {
  const request = new Request('http://localhost/api/auth/me', {
    headers: { Cookie: 'earth_session=cookie-token' },
  });

  assert.equal(extractToken(request), 'cookie-token');
});

test('blank bearer credentials fall back to the session cookie', () => {
  const request = new Request('http://localhost/api/auth/me', {
    headers: {
      Cookie: 'earth_session=cookie-token',
      Authorization: 'Bearer   ',
    },
  });

  assert.equal(extractToken(request), 'cookie-token');
});
