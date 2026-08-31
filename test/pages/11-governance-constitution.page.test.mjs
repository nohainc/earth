import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { createProposal, castVote, challengeProposal } from "../../cloudflare/src/governance-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 11: Democratic Governance, Balloting & Earth Constitution", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  const TEST_CITY_ID = "CITY-GOV-TEST";
  let proposalId = "";

  t.after(async () => {
    try {
      await repo.query("UPDATE memberships SET city_id = 'CITY-0084' WHERE human_id = $1", [TEST_HUMAN_ID]);
      await repo.query("DELETE FROM ballots WHERE proposal_id IN (SELECT id FROM proposals WHERE institution_id = $1)", [TEST_CITY_ID]);
      await repo.query("DELETE FROM proposals WHERE institution_id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM governance_rules WHERE institution_id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM account_balances WHERE owner_id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM cities WHERE id = $1", [TEST_CITY_ID]);
      await repo.query("DELETE FROM institutions WHERE id = $1", [TEST_CITY_ID]);
    } finally {
      await client.end();
    }
  });

  await t.test("TC-11.1: Provision Democratic Municipality & Baseline Rule", async () => {
    await repo.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CITY', 'Democratic Metro', 'active') ON CONFLICT (id) DO NOTHING", [TEST_CITY_ID]);
    await repo.query("INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury) VALUES ($1, $1, 10, 50, 50, 50, 50, 100000.00) ON CONFLICT (id) DO NOTHING", [TEST_CITY_ID]);
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 50000.00, 'CREDIT') ON CONFLICT (account_id) DO NOTHING", [`account-city-${TEST_CITY_ID}`, TEST_CITY_ID]);
    await repo.query("INSERT INTO memberships (human_id, city_id, joined_game_day) VALUES ($1, $2, 1) ON CONFLICT (human_id) DO UPDATE SET city_id = $2", [TEST_HUMAN_ID, TEST_CITY_ID]);
    await repo.query("UPDATE humans SET political_eligibility_game_day = 0 WHERE id = $1", [TEST_HUMAN_ID]);
  });

  await t.test("TC-11.2: Create Civic Proposal with Auto-Baseline Quorum", async () => {
    const correlationId = "gov-prop-" + Date.now();
    const res = await createProposal(repo, {
      humanId: TEST_HUMAN_ID,
      institutionId: TEST_CITY_ID,
      title: "Clean Energy Infrastructure Expansion Act",
      body: "Mandates 25% allocation of municipal surplus to geothermal power.",
      durationHours: 72,
      targetCategory: null,
      targetValue: null,
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.proposal.id);
    proposalId = res.proposal.id;
    assert.equal(res.proposal.status, "open");
  });

  await t.test("TC-11.3: Cast Democratic Weighted Vote", async () => {
    assert.ok(proposalId);

    const res = await castVote(repo, {
      proposalId,
      humanId: TEST_HUMAN_ID,
      choice: "support",
    });

    assert.equal(res.ok, true);
    assert.equal(res.vote, "support");
  });

  await t.test("TC-11.4: File Constitutional Challenge & Impose Injunction", async () => {
    assert.ok(proposalId);

    // Transition proposal to passed status to test judicial challenge
    await repo.query("UPDATE proposals SET status = 'closed', outcome = 'passed', execution_status = 'ready' WHERE id = $1", [proposalId]);

    const res = await challengeProposal(repo, {
      humanId: TEST_HUMAN_ID,
      proposalId,
      reason: "Proposed allocation conflicts with Municipal Charter Section 4.2",
      correlationId: "challenge-" + Date.now(),
    });

    assert.equal(res.ok, true);
    assert.equal(res.executionStatus, "challenged");
  });
});
