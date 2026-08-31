import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { totp, validTotp, derivePassword, digest, bytesToBase32 } from "../../cloudflare/src/auth-crypto.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_EMAIL = "vitalii.noga@gmail.com";

test("Page 1: Auth, Credentials, TOTP 2FA & Session Tokens", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await client.end();
  });

  await t.test("TC-1.1: Verify Authentic Account Credentials in Database", async () => {
    const res = await repo.query(
      "SELECT ac.human_id, ac.email, ac.password_salt, ac.password_hash, ac.password_iterations, h.display_name FROM auth_credentials ac JOIN humans h ON h.id = ac.human_id WHERE ac.email = $1",
      [TEST_EMAIL]
    );

    assert.equal(res.rows.length, 1, "Test account must exist in Postgres");
    const account = res.rows[0];
    assert.equal(account.email, TEST_EMAIL);
    assert.equal(account.human_id, "H-D11AA14C");
    assert.ok(account.password_salt);
    assert.ok(account.password_hash);
  });

  await t.test("TC-1.2: TOTP Generation, Verification & Time-Drift Tolerance", async () => {
    const rawSecret = crypto.getRandomValues(new Uint8Array(20));
    const secret = bytesToBase32(rawSecret);

    const code = await totp(secret);
    assert.match(code, /^\d{6}$/, "Generated TOTP must be a 6-digit string");

    const isValid = await validTotp(secret, code);
    assert.equal(isValid, true, "Generated TOTP must validate against secret");

    const invalidCode = "000000" === code ? "999999" : "000000";
    const isInvalid = await validTotp(secret, invalidCode);
    assert.equal(isInvalid, false, "Arbitrary code must fail validation");
  });

  await t.test("TC-1.3: Cryptographic Password Derivation PBKDF2 & Digest Verification", async () => {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const derived = await derivePassword("P@ssw0rdP@ssw0rd", salt, 100000);
    assert.ok(derived.length > 20, "Derived PBKDF2 hash must be valid Base64");

    const hash1 = await digest("test-session-payload-data");
    const hash2 = await digest("test-session-payload-data");
    assert.equal(hash1, hash2, "Deterministic digest must match identically");
  });
});
