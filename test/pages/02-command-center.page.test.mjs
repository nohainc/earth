import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { listNotifications } from "../../cloudflare/src/read-postgres.ts";
import { generateDecisionQueue } from "../../cloudflare/src/decision-queue.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 2: Command Center, Decision Queue & World Vitals", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await client.end();
  });

  await t.test("TC-2.1: World Vitals & Planetary Health Status", async () => {
    const worldRes = await repo.query("SELECT * FROM world_state WHERE id = 'WORLD'");
    assert.ok(worldRes.rows[0], "World state row must exist");
    const world = worldRes.rows[0];
    assert.ok(typeof world.game_day === "number" || typeof world.game_day === "string");
  });

  await t.test("TC-2.2: Fetch User Notifications & Activity Stream", async () => {
    const notifs = await listNotifications(repo, TEST_HUMAN_ID, 20);
    assert.ok(Array.isArray(notifs.notifications), "Notifications list must be returned");
    assert.ok(typeof notifs.unread === "number", "Unread count must be numeric");
  });

  await t.test("TC-2.3: Decision Queue Prioritization & Domain Actions", async () => {
    const queue = generateDecisionQueue({
      city: {
        id: "CITY-0084",
        residents: 500,
        energy_capacity: 100,
        health_capacity: 50,
      },
      finance: {
        unpaid_tax: 250.00,
        status: "overdue",
      },
      business: {
        id: "B-TEST-01",
        condition: 45,
      },
    });

    assert.ok(Array.isArray(queue), "Decision queue must be an array");
    assert.ok(queue.length >= 1, "Should identify actionable items for low energy/tax");
    const topItem = queue[0];
    assert.ok(topItem.id);
    assert.ok(topItem.title);
    assert.ok(topItem.riskLevel);
  });
});
