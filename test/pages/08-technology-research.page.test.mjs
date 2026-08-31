import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { fundResearchProject, adoptTechnology } from "../../cloudflare/src/technology-postgres.ts";
import { createBusiness } from "../../cloudflare/src/business-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 8: Technology Catalog, Research Crowdfunding & Business Adoption", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let tempBizId = "";
  let techId = "TECH-SOLAR-01";
  let projId = "PROJECT-SOLAR-01";

  t.after(async () => {
    if (tempBizId) {
      await repo.query("DELETE FROM business_technology_adoptions WHERE business_id = $1", [tempBizId]);
      await repo.query("DELETE FROM business_shares WHERE business_id = $1", [tempBizId]);
      await repo.query("DELETE FROM business_financials WHERE business_id = $1", [tempBizId]);
      await repo.query("DELETE FROM business_management WHERE business_id = $1", [tempBizId]);
      await repo.query("DELETE FROM business_constitutions WHERE business_id = $1", [tempBizId]);
      await repo.query("DELETE FROM businesses WHERE id = $1", [tempBizId]);
    }
    await repo.query("DELETE FROM research_projects WHERE id = $1", [projId]);
    await repo.query("DELETE FROM technologies WHERE id = $1", [techId]);
    await client.end();
  });

  await t.test("TC-8.1: Setup Approved Research Project Record", async () => {
    await repo.query("INSERT INTO memberships (human_id, city_id, joined_game_day) VALUES ($1, 'CITY-0084', 1) ON CONFLICT (human_id) DO UPDATE SET city_id = 'CITY-0084', joined_game_day = 1", [TEST_HUMAN_ID]);
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ('account-research-registry', 'OUC', 100000.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING");
    await repo.query("INSERT INTO technologies (id, owner_id, name, progress) VALUES ($1, $2, 'Clean Energy Systems', 10) ON CONFLICT (id) DO UPDATE SET name = 'Clean Energy Systems', progress = 10, owner_id = $2", [techId, TEST_HUMAN_ID]);
    await repo.query("INSERT INTO research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day, focus) VALUES ($1, $2, $3, 1000, 10, 'active', 1, 'efficiency') ON CONFLICT (id) DO UPDATE SET budget = 1000, progress = 10", [projId, techId, TEST_HUMAN_ID]);
    await repo.query("UPDATE account_balances SET balance = balance + 5000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);
  });

  await t.test("TC-8.2: Crowdfund Research Project Progress", async () => {
    const res = await fundResearchProject(repo, {
      ownerId: TEST_HUMAN_ID,
      amount: 250.00,
      correlationId: "fund-tech-" + Date.now(),
    });

    assert.equal(res.ok, true);
    assert.ok(Number(res.technology.progress) > 10, "Progress must advance with credit funding");
  });

  await t.test("TC-8.3: Adopt Fully Researched Technology for Active Business", async () => {
    await repo.query("UPDATE technologies SET progress = 100 WHERE id = $1", [techId]);

    const bizRes = await createBusiness(repo, {
      ownerId: TEST_HUMAN_ID,
      name: "Solaris Power Labs " + Date.now(),
      sector: "energy",
      capitalCityId: "CITY-0084",
      correlationId: "biz-tech-adopt-" + Date.now(),
    });
    tempBizId = bizRes.business.id;

    const adoptRes = await adoptTechnology(repo, {
      humanId: TEST_HUMAN_ID,
      businessId: tempBizId,
      technologyId: techId,
    });

    assert.equal(adoptRes.ok, true);
    assert.equal(adoptRes.businessId, tempBizId);
  });
});
