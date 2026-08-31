import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { createCommunity, updateCommunity, contributeToCommunity, disbandCommunity } from "../../cloudflare/src/communities-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 10: Founding Communities, Admission Charters & Roles", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let createdCommId = "";

  t.after(async () => {
    if (createdCommId) {
      await repo.query("DELETE FROM ledger_entries WHERE reason_id = $1", [createdCommId]);
      await repo.query("DELETE FROM community_members WHERE community_id = $1", [createdCommId]);
      await repo.query("DELETE FROM communities WHERE id = $1", [createdCommId]);
    }
    await client.end();
  });

  await t.test("TC-10.1: Form Founding Community with Open Admission", async () => {
    const correlationId = "comm-form-" + Date.now();
    const res = await createCommunity(repo, {
      founderId: TEST_HUMAN_ID,
      name: "Solar Pioneers Alliance",
      description: "Cooperative for solar infrastructure expansion.",
      admissionPolicy: "open",
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.community.id);
    createdCommId = res.community.id;
    assert.equal(res.community.name, "Solar Pioneers Alliance");
  });

  await t.test("TC-10.2: Update Community Charter & Admission Policy", async () => {
    assert.ok(createdCommId);

    const res = await updateCommunity(repo, {
      communityId: createdCommId,
      humanId: TEST_HUMAN_ID,
      description: "Updated charter for solar energy sovereignty.",
      admissionPolicy: "approval",
    });

    assert.equal(res.ok, true);
    assert.equal(res.community.admission_policy, "approval");
  });

  await t.test("TC-10.3: Contribute Credits to Community Treasury", async () => {
    assert.ok(createdCommId);
    await repo.query("UPDATE account_balances SET balance = balance + 1000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);

    const res = await contributeToCommunity(repo, {
      communityId: createdCommId,
      humanId: TEST_HUMAN_ID,
      amount: 250.00,
      correlationId: "contrib-" + Date.now(),
    });

    assert.equal(res.ok, true);
    assert.equal(Number(res.community.shared_credits), 250);
  });
});
