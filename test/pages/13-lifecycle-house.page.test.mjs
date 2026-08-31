import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { registerSuccessor, clearSuccessor } from "../../cloudflare/src/lifecycle-postgres.ts";
import { updateHouseMotto } from "../../cloudflare/src/house-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";
const TEST_EMAIL = "vitalii.noga@gmail.com";
const SUCCESSOR_ID = "H-SUCCESSOR-TEST";

test("Page 13: Citizen Lifecycle, Succession & House Dynasty", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await clearSuccessor(repo, TEST_HUMAN_ID).catch(() => null);
    await repo.query("DELETE FROM humans WHERE id = $1", [SUCCESSOR_ID]);
    await repo.query("DELETE FROM account_balances WHERE owner_id = $1", [SUCCESSOR_ID]);
    await client.end();
  });

  await t.test("TC-13.1: Register Succession Plan for Inheritance", async () => {
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ('account-h-successor-test', $1, 100.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING", [SUCCESSOR_ID]);
    await repo.query("INSERT INTO humans (id, account_id, display_name, life_status) VALUES ($1, 'account-h-successor-test', 'Elena Noga', 'active') ON CONFLICT (id) DO UPDATE SET life_status = 'active'", [SUCCESSOR_ID]);

    const res = await registerSuccessor(repo, {
      humanId: TEST_HUMAN_ID,
      successorName: "Elena Noga",
      successorHumanId: SUCCESSOR_ID,
      estatePeriodDays: 30,
      currentLifeStatus: "active",
    });

    assert.equal(res.ok, true);
    assert.ok(res.successor);
    assert.equal(res.successor.successor_human_id, SUCCESSOR_ID);

    // Verify clear successor
    const clearRes = await clearSuccessor(repo, TEST_HUMAN_ID);
    assert.equal(clearRes.ok, true);
  });

  await t.test("TC-13.2: Update House Motto & Lineage Records", async () => {
    await repo.query("INSERT INTO houses (id, email, house_name, legacy_points) VALUES ('HOUSE-TEST', $1, 'House of Noga', 500) ON CONFLICT (email) DO UPDATE SET legacy_points = 500", [TEST_EMAIL]);

    const res = await updateHouseMotto(
      repo,
      TEST_EMAIL,
      "Per Aspera Ad Astra",
      "House of Noga",
      "motto-" + Date.now()
    );

    assert.equal(res.ok, true);
    assert.equal(res.motto, "Per Aspera Ad Astra");
  });
});
