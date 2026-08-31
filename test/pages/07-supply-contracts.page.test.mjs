import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { proposeSupplyContract, acceptSupplyContract } from "../../cloudflare/src/supply-contracts-postgres.ts";
import { openDispute } from "../../cloudflare/src/contracts-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";
const COUNTERPARTY_ID = "TEST-H-001";

test("Page 7: B2B Supply Contracts & Dispute Arbitration", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let createdContractId = "";
  let disputeId = "";

  t.after(async () => {
    if (disputeId) {
      await repo.query("DELETE FROM contract_disputes WHERE id = $1", [disputeId]);
    }
    if (createdContractId) {
      await repo.query("DELETE FROM contract_escrow_vaults WHERE contract_id = $1", [createdContractId]);
      await repo.query("DELETE FROM supply_contracts WHERE contract_id = $1", [createdContractId]);
      await repo.query("DELETE FROM negotiated_contracts WHERE id = $1", [createdContractId]);
    }
    await client.end();
  });

  await t.test("TC-7.0: Setup Credit Balances for Counterparty & User", async () => {
    await repo.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ('account-h-test-001', $1, 10000.00, 'CREDIT') ON CONFLICT (account_id) DO UPDATE SET balance = 10000.00", [COUNTERPARTY_ID]);
    await repo.query("UPDATE account_balances SET balance = balance + 10000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);
  });

  await t.test("TC-7.1: Propose B2B Supply Contract with Structured Terms", async () => {
    const correlationId = "contract-prop-" + Date.now();
    const res = await proposeSupplyContract(repo, {
      proposerId: TEST_HUMAN_ID,
      counterpartyId: COUNTERPARTY_ID,
      proposerRole: "buyer",
      resourceType: "material",
      dailyQuantity: 10,
      unitPrice: 2.25,
      totalDays: 14,
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.contractId);
    createdContractId = res.contractId;
  });

  await t.test("TC-7.2: Counterparty Accepts Supply Contract", async () => {
    assert.ok(createdContractId);

    const res = await acceptSupplyContract(repo, createdContractId, COUNTERPARTY_ID);

    assert.equal(res.ok, true);
    assert.equal(res.status, "accepted");
  });

  await t.test("TC-7.3: Open Dispute & Trigger Judicial Injunction", async () => {
    assert.ok(createdContractId);

    const res = await openDispute(repo, {
      contractId: createdContractId,
      claimantId: TEST_HUMAN_ID,
      reason: "Material shipment quality verification failure",
    });

    assert.equal(res.ok, true);
    assert.ok(res.dispute.id);
    disputeId = res.dispute.id;
    assert.equal(res.dispute.status, "open");
  });
});
