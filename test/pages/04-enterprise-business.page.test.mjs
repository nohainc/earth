import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { createBusiness, setPolicy, distributeDividends } from "../../cloudflare/src/business-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 4: Business Formation, Enterprise Management & Dividends", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let createdBusinessId = "";

  t.after(async () => {
    if (createdBusinessId) {
      await repo.query("DELETE FROM business_shares WHERE business_id = $1", [createdBusinessId]);
      await repo.query("DELETE FROM business_financials WHERE business_id = $1", [createdBusinessId]);
      await repo.query("DELETE FROM business_management WHERE business_id = $1", [createdBusinessId]);
      await repo.query("DELETE FROM business_constitutions WHERE business_id = $1", [createdBusinessId]);
      await repo.query("DELETE FROM businesses WHERE id = $1", [createdBusinessId]);
      await repo.query("DELETE FROM institutions WHERE id = $1", [createdBusinessId]);
    }
    await client.end();
  });

  await t.test("TC-4.0: Ensure City Residency & Credit Balance", async () => {
    await repo.query("INSERT INTO memberships (human_id, city_id, joined_game_day) VALUES ($1, 'CITY-0084', 1) ON CONFLICT (human_id) DO UPDATE SET city_id = 'CITY-0084', joined_game_day = 1", [TEST_HUMAN_ID]);
    await repo.query("UPDATE account_balances SET balance = balance + 5000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);
  });

  await t.test("TC-4.1: Business Formation & Controlling Share Issuance", async () => {
    const correlationId = "biz-form-" + Date.now();
    const res = await createBusiness(repo, {
      ownerId: TEST_HUMAN_ID,
      name: "Aether Dynamics & Systems " + Date.now(),
      sector: "energy",
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.business.id);
    createdBusinessId = res.business.id;
    assert.equal(res.shares, 100);
  });

  await t.test("TC-4.2: Operating Policy Update & Financial Multiplier", async () => {
    assert.ok(createdBusinessId);

    const res = await setPolicy(repo, {
      humanId: TEST_HUMAN_ID,
      businessId: createdBusinessId,
      policy: "revenue",
    });

    assert.equal(res.ok, true);
    assert.equal(res.policy, "revenue");
  });

  await t.test("TC-4.3: Pro-Rata Dividend Distribution", async () => {
    assert.ok(createdBusinessId);

    await repo.query(
      "UPDATE account_balances SET balance = balance + 5000.00 WHERE owner_id = $1 AND currency = 'CREDIT'",
      [TEST_HUMAN_ID]
    );

    const correlationId = "div-dist-" + Date.now();
    const res = await distributeDividends(repo, {
      callerId: TEST_HUMAN_ID,
      businessId: createdBusinessId,
      totalAmount: "500.00",
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.equal(res.totalAmount, "500.00");
  });
});
