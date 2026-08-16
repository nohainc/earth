const encoder = new TextEncoder();
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export const SESSION_DAYS = 7;

export function bytesToBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

export function base64ToBytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

export function bytesToBase32(bytes: Uint8Array): string {
  let output = '';
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += base32Alphabet[(buffer >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += base32Alphabet[(buffer << (5 - bits)) & 31];
  return output;
}

export function base32ToBytes(value: string): Uint8Array {
  let buffer = 0;
  let bits = 0;
  const output: number[] = [];
  for (const char of value.replace(/=+$/, '').toUpperCase()) {
    const index = base32Alphabet.indexOf(char);
    if (index < 0) continue;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      output.push((buffer >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(output);
}

export async function totp(secret: string, timestamp = Date.now()): Promise<string> {
  const counter = Math.floor(timestamp / 30000);
  const data = new ArrayBuffer(8);
  const view = new DataView(data);
  view.setUint32(4, counter);
  const key = await crypto.subtle.importKey(
    'raw',
    base32ToBytes(secret),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const hash = new Uint8Array(await crypto.subtle.sign('HMAC', key, data));
  const offset = hash[hash.length - 1] & 15;
  const value =
    ((hash[offset] & 127) << 24) |
    ((hash[offset + 1] << 16) |
    ((hash[offset + 2] << 8) | hash[offset + 3]));
  return String(value % 1000000).padStart(6, '0');
}

export async function validTotp(secret: string, code: string): Promise<boolean> {
  if (!/^\d{6}$/.test(code)) return false;
  for (const drift of [-30000, 0, 30000]) {
    if (code === (await totp(secret, Date.now() + drift))) return true;
  }
  return false;
}

export async function derivePassword(password: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256);
  return bytesToBase64(new Uint8Array(bits));
}

export async function digest(value: string): Promise<string> {
  return bytesToBase64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))));
}
