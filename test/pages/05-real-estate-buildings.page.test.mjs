import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { purchasePrivatePlotAndConstruct, setBuildingOperatingPolicy, setBuildingAutoRepair, demolishBuilding } from "../../cloudflare/src/real-estate-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 5: Real Estate, Buildings Hub & Operating Policies", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  const TEST_CITY_ID = "CITY-PAGE5-TEST";
  let createdBuildingId = "";

  t.after(async () => {
    try {
      await repo.query("UPDATE memberships SET city_id = 'CITY-0084' WHERE human_id = $1", [TEST_HUMAN_ID]);
      if (createdBuildingId) {
        await repo.query("DELETE FROM buildings WHERE id = $1", [createdBuildingId]);
      }
      await repo.query("DELETE FROM account_balances WHERE owner_id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM cities WHERE id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM institutions WHERE id = $1", [TEST_CITY_ID]);
    } finally {
      await client.end();
    }
  });

  await t.test("TC-5.1: Setup Clean City & Seed Private Land", async () => {
    await repo.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CITY', 'Page 5 Test District', 'active') ON CONFLICT (id) DO NOTHING", [TEST_CITY_ID]);
    await repo.query("INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury) VALUES ($1, $1, 10, 50, 50, 50, 50, 100000.00) ON CONFLICT (id) DO UPDATE SET residents = 10, housing_capacity = 50", [TEST_CITY_ID]);
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 50000.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING", [`account-city-${TEST_CITY_ID}`, TEST_CITY_ID]);
    await repo.query("INSERT INTO memberships (human_id, city_id, joined_game_day) VALUES ($1, $2, 1) ON CONFLICT (human_id) DO UPDATE SET city_id = $2, joined_game_day = 1", [TEST_HUMAN_ID, TEST_CITY_ID]);
    await repo.query("INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1, 'material', 5000.0) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + 5000.0", [TEST_HUMAN_ID]);
    await repo.query("UPDATE account_balances SET balance = balance + 50000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);
  });

  await t.test("TC-5.2: Purchase Private Plot & Construct Facility", async () => {
    const correlationId = "bld-purchase-" + Date.now();
    const res = await purchasePrivatePlotAndConstruct(repo, {
      ownerId: TEST_HUMAN_ID,
      cityId: TEST_CITY_ID,
      buildingType: "restaurant",
      name: "Page 5 Bistro Facility",
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.building.id);
    createdBuildingId = res.building.id;
    assert.equal(res.building.status, "under_construction");
    assert.equal(res.building.building_type, "restaurant");
  });

  await t.test("TC-5.3: Operating Policy Update & Auto-Repair Toggle", async () => {
    assert.ok(createdBuildingId);

    const polRes = await setBuildingOperatingPolicy(repo, {
      humanId: TEST_HUMAN_ID,
      buildingId: createdBuildingId,
      policy: "high_output",
    });
    assert.equal(polRes.ok, true);
    assert.equal(polRes.policy, "high_output");

    const autoRes = await setBuildingAutoRepair(repo, {
      humanId: TEST_HUMAN_ID,
      buildingId: createdBuildingId,
      autoRepairEnabled: false,
    });
    assert.equal(autoRes.ok, true);
    assert.equal(autoRes.autoRepairEnabled, false);
  });

  await t.test("TC-5.4: Demolish Building & Release City Zoning Slots", async () => {
    assert.ok(createdBuildingId);

    const res = await demolishBuilding(repo, {
      humanId: TEST_HUMAN_ID,
      buildingId: createdBuildingId,
    });

    assert.equal(res.ok, true);
    assert.ok(typeof res.freedSlots === "number");
    await repo.query("DELETE FROM buildings WHERE id = $1", [createdBuildingId]);
    createdBuildingId = "";
  });
});
