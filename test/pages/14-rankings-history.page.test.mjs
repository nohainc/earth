import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { listRankings, listHistory, listPantheonOfAchievements } from "../../cloudflare/src/read-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";

test("Page 14: Planetary Rankings, Historical Archive & Pantheon", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await client.end();
  });

  await t.test("TC-14.1: Query Planetary Rankings (Cities, Corps, Citizens)", async () => {
    const rankings = await listRankings(repo);

    assert.ok(Array.isArray(rankings.cities), "City rankings list must exist");
    assert.ok(Array.isArray(rankings.corporations), "Corporation rankings list must exist");
    assert.ok(Array.isArray(rankings.citizens), "Citizen rankings list must exist");
  });

  await t.test("TC-14.2: Query Planetary Historical Timeline & Major Events", async () => {
    const history = await listHistory(repo, 20);

    assert.ok(Array.isArray(history.events), "World events list must exist");
  });

  await t.test("TC-14.3: Query Pantheon of Living Legends & Achievements", async () => {
    const pantheon = await listPantheonOfAchievements(repo);

    assert.ok(Array.isArray(pantheon.livingLeaders), "Living leaders list must exist");
    assert.ok(Array.isArray(pantheon.deceasedPantheon), "Deceased pantheon list must exist");
    assert.ok(Array.isArray(pantheon.houses), "Houses list must exist");
  });
});
