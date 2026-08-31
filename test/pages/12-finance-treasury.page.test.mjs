import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { publicSpending, settleTax } from "../../cloudflare/src/finance-postgres.ts";
import { recordDailyNetWorthSnapshot } from "../../cloudflare/src/net-worth-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 12: Personal Finance, Taxation & Municipal Treasury", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  t.after(async () => {
    await client.end();
  });

  await t.test("TC-12.1: Public Treasury Spending with Mayor Role", async () => {
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ('account-ouc-treasury', 'OUC', 1000000.00, 'CREDIT') ON CONFLICT (account_id) DO UPDATE SET balance = account_balances.balance + 50000.00");
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ('account-city-CITY-0084', 'CITY-0084', 50000.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING");
    await repo.query("INSERT INTO institution_roles (id, institution_id, name) VALUES ('ROLE-MAYOR-0084', 'CITY-0084', 'City Mayor') ON CONFLICT (id) DO NOTHING");
    await repo.query("INSERT INTO role_assignments (id, role_id, human_id, institution_id, status, started_game_day, ends_game_day) VALUES ('ROLE-ASSIGN-MAYOR', 'ROLE-MAYOR-0084', $1, 'CITY-0084', 'active', 1, 99999) ON CONFLICT (id) DO UPDATE SET status = 'active', ends_game_day = 99999", [TEST_HUMAN_ID]);

    const correlationId = "pub-spend-" + Date.now();
    const res = await publicSpending(repo, {
      actorId: TEST_HUMAN_ID,
      cityId: "CITY-0084",
      category: "healthcare",
      amount: 150.00,
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.equal(res.amount, 150.00);
  });

  await t.test("TC-12.2: Settle Personal Tax Obligation", async () => {
    await repo.query("UPDATE account_balances SET balance = balance + 500.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);
    await repo.query("INSERT INTO tax_rules (id, scope, category, rate, version, active) VALUES ('TAX-OUC-BASIC', 'universal', 'income', 0.05, 1, true) ON CONFLICT (id) DO UPDATE SET rate = 0.05");

    const res = await settleTax(repo, TEST_HUMAN_ID, 100.00);

    assert.equal(res.ok, true);
  });

  await t.test("TC-12.3: Record Daily Net Worth Snapshot for Chart Analytics", async () => {
    const res = await recordDailyNetWorthSnapshot(repo, TEST_HUMAN_ID, 14528);

    assert.equal(res.ok, true);
    assert.ok(res.snapshot);
    assert.ok(typeof res.snapshot.total_net_worth === "number" || typeof res.snapshot.total_net_worth === "string");
  });
});
