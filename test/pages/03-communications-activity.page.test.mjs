import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { sendDiplomaticDispatch, markDispatchRead, getCommunicationsMetrics } from "../../cloudflare/src/communications-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";
const RECIPIENT_ID = "TEST-H-001";

test("Page 3: Communications, Diplomatic Dispatch & Activity Notifications", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let createdDispatchId = "";

  t.after(async () => {
    if (createdDispatchId) {
      await repo.query("DELETE FROM diplomatic_dispatches WHERE id = $1", [createdDispatchId]);
    }
    await client.end();
  });

  await t.test("TC-3.1: Send & Ingest Diplomatic Dispatch", async () => {
    const correlationId = "dispatch-test-" + Date.now();
    const res = await sendDiplomaticDispatch(
      repo,
      TEST_HUMAN_ID,
      RECIPIENT_ID,
      "Inter-City Trade Agreement Negotiation",
      "Proposed bilateral commodity tariff reduction terms.",
      "diplomatic",
      { priority: "urgent" },
      1,
      0,
      correlationId
    );

    assert.ok(res.id, "Dispatch ID must be created");
    createdDispatchId = res.id;
    assert.equal(res.subject, "Inter-City Trade Agreement Negotiation");
    assert.equal(res.status, "unread");
  });

  await t.test("TC-3.2: Mark Dispatch Read & Verify State Update", async () => {
    assert.ok(createdDispatchId);

    const ok = await markDispatchRead(repo, RECIPIENT_ID, createdDispatchId);
    assert.equal(ok, true);

    const check = await repo.query("SELECT status, read_at FROM diplomatic_dispatches WHERE id = $1", [createdDispatchId]);
    assert.equal(check.rows[0]?.status, "read");
    assert.ok(check.rows[0]?.read_at);
  });

  await t.test("TC-3.3: Query Communications Metrics", async () => {
    const metrics = await getCommunicationsMetrics(repo, TEST_HUMAN_ID);
    assert.ok(typeof metrics.unreadDispatches === "number");
    assert.ok(typeof metrics.activeChannelsCount === "number");
  });
});
