import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { changeCityResidency, setCityTaxCharter } from "../../cloudflare/src/institutions-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 9: Institutions Hub, Municipal Charters & Corporation Formation", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  const CITY_A = "CITY-INST-A-TEST";
  const CITY_B = "CITY-INST-B-TEST";

  t.after(async () => {
    try {
      await repo.query("UPDATE memberships SET city_id = 'CITY-0084' WHERE human_id = $1", [TEST_HUMAN_ID]);
      await repo.query("DELETE FROM role_assignments WHERE institution_id IN ($1, $2)", [CITY_A, CITY_B]);
      await repo.query("DELETE FROM institution_roles WHERE institution_id IN ($1, $2)", [CITY_A, CITY_B]);
      await repo.query("DELETE FROM account_balances WHERE owner_id IN ($1, $2)", [CITY_A, CITY_B]);
      await repo.query("DELETE FROM cities WHERE id IN ($1, $2)", [CITY_A, CITY_B]);
      await repo.query("DELETE FROM institutions WHERE id IN ($1, $2)", [CITY_A, CITY_B]);
    } finally {
      await client.end();
    }
  });

  await t.test("TC-9.1: Provision Municipal Districts", async () => {
    await repo.query("UPDATE memberships SET corporation_id = NULL WHERE human_id = $1", [TEST_HUMAN_ID]);
    await repo.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CITY', 'District Alpha', 'active'), ($2, 'CITY', 'District Beta', 'active') ON CONFLICT (id) DO NOTHING", [CITY_A, CITY_B]);
    await repo.query("INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury) VALUES ($1, $1, 10, 50, 50, 50, 50, 100000.00), ($2, $2, 10, 50, 50, 50, 50, 100000.00) ON CONFLICT (id) DO NOTHING", [CITY_A, CITY_B]);
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 50000.00, 'CREDIT'), ($3, $4, 50000.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING", [`account-city-${CITY_A}`, CITY_A, `account-city-${CITY_B}`, CITY_B]);
  });

  await t.test("TC-9.2: Change City Residency & Move Across Districts", async () => {
    const resA = await changeCityResidency(repo, {
      humanId: TEST_HUMAN_ID,
      cityId: CITY_A,
      action: 'join',
    });
    assert.equal(resA.ok, true);

    const memA = await repo.query("SELECT city_id FROM memberships WHERE human_id = $1", [TEST_HUMAN_ID]);
    assert.equal(memA.rows[0]?.city_id, CITY_A);

    const resB = await changeCityResidency(repo, {
      humanId: TEST_HUMAN_ID,
      cityId: CITY_B,
      action: 'join',
    });
    assert.equal(resB.ok, true);

    const memB = await repo.query("SELECT city_id FROM memberships WHERE human_id = $1", [TEST_HUMAN_ID]);
    assert.equal(memB.rows[0]?.city_id, CITY_B);
  });

  await t.test("TC-9.3: Update Municipal Tax Charter with Safe Bound Clamping", async () => {
    await repo.query("INSERT INTO institution_roles (id, institution_id, name) VALUES ('ROLE-MAYOR-CITY-B', $1, 'City Mayor') ON CONFLICT (id) DO NOTHING", [CITY_B]);
    await repo.query("INSERT INTO role_assignments (id, role_id, human_id, institution_id, status, started_game_day, ends_game_day) VALUES ('ROLE-ASSIGN-MAYOR-B', 'ROLE-MAYOR-CITY-B', $1, $2, 'active', 1, 99999) ON CONFLICT (id) DO UPDATE SET status = 'active', ends_game_day = 99999", [TEST_HUMAN_ID, CITY_B]);

    const res = await setCityTaxCharter(repo, {
      cityId: CITY_B,
      humanId: TEST_HUMAN_ID,
      salesTax: 0.05,
      incomeTax: 0.10,
    });

    assert.equal(res.ok, true);
    assert.ok(res.charter);
  });
});
