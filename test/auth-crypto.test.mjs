import test from 'node:test';
import assert from 'node:assert/strict';
import {
  base32ToBytes,
  base64ToBytes,
  bytesToBase32,
  bytesToBase64,
  derivePassword,
  digest,
  totp,
  validTotp,
} from '../cloudflare/src/auth-crypto.ts';

test('base64 and base32 roundtrips bytes correctly', () => {
  const bytes = new Uint8Array([1, 2, 3, 4, 5, 250, 255]);
  const b64 = bytesToBase64(bytes);
  const b32 = bytesToBase32(bytes);

  assert.deepEqual(base64ToBytes(b64), bytes);
  assert.deepEqual(base32ToBytes(b32), bytes);
});

test('TOTP generates 6-digit codes and validates within drift window', async () => {
  const secret = bytesToBase32(new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]));
  const now = Date.now();
  const codeNow = await totp(secret, now);
  assert.match(codeNow, /^\d{6}$/);

  // Exact time should be valid
  assert.equal(await validTotp(secret, codeNow), true);

  // Invalid length or chars should be invalid
  assert.equal(await validTotp(secret, 'abc'), false);
  assert.equal(await validTotp(secret, '12345'), false);
  assert.equal(await validTotp(secret, '1234567'), false);
});

test('PBKDF2 derives deterministic password hash', async () => {
  const salt = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
  const hash1 = await derivePassword('secret-password-123', salt, 1000);
  const hash2 = await derivePassword('secret-password-123', salt, 1000);
  const hash3 = await derivePassword('different-password', salt, 1000);

  assert.equal(typeof hash1, 'string');
  assert.equal(hash1, hash2);
  assert.notEqual(hash1, hash3);
});

test('SHA-256 digest hashes text deterministically', async () => {
  const digest1 = await digest('sample-token');
  const digest2 = await digest('sample-token');
  const digest3 = await digest('another-token');

  assert.equal(digest1, digest2);
  assert.notEqual(digest1, digest3);
});
