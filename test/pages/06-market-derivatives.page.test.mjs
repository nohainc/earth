import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "pg";
import { PostgresRepository } from "../../cloudflare/src/repository.ts";
import { submitMarketOrder, cancelMarketOrder, listMarketOrders } from "../../cloudflare/src/market-postgres.ts";
import { createFuturesListing, cancelFuturesListing } from "../../cloudflare/src/derivatives-postgres.ts";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://earth:earth_dev_only@localhost:5432/earth";
const TEST_HUMAN_ID = "H-D11AA14C";

test("Page 6: Commodity Exchange, Orderbook & Derivatives Market", async (t) => {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repo = new PostgresRepository(client);

  let placedOrderId = "";
  let placedContractId = "";

  t.after(async () => {
    if (placedOrderId) {
      await repo.query("DELETE FROM market_orders WHERE id = $1", [placedOrderId]);
    }
    if (placedContractId) {
      await repo.query("DELETE FROM commodity_futures_contracts WHERE id = $1", [placedContractId]);
    }
    await client.end();
  });

  await t.test("TC-6.1: Submit Commodity Buy Order with Escrow Reservation", async () => {
    await repo.query("UPDATE account_balances SET balance = balance + 10000.00 WHERE owner_id = $1 AND currency = 'CREDIT'", [TEST_HUMAN_ID]);

    const correlationId = "mkt-order-" + Date.now();
    const res = await submitMarketOrder(repo, {
      humanId: TEST_HUMAN_ID,
      product: "food",
      side: "buy",
      quantity: 25,
      limitPrice: 3.50,
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.order.id);
    placedOrderId = res.order.id;
    assert.equal(res.order.status, "open");
    assert.equal(res.order.product, "food");
  });

  await t.test("TC-6.2: Query Active Orderbook & User Orders", async () => {
    const list = await listMarketOrders(repo, "food");
    assert.ok(Array.isArray(list.orders));
    const found = list.orders.find((o) => o.id === placedOrderId);
    assert.ok(found, "Placed order must be present in orderbook list");
  });

  await t.test("TC-6.3: Cancel Order & Refund Escrow Credits", async () => {
    assert.ok(placedOrderId);

    const res = await cancelMarketOrder(repo, {
      orderId: placedOrderId,
      humanId: TEST_HUMAN_ID,
    });

    assert.equal(res.ok, true);
    assert.equal(res.orderId, placedOrderId);
    placedOrderId = "";
  });

  await t.test("TC-6.4: List Commodity Futures Contract for Hedging", async () => {
    await repo.query("INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1, 'energy', 1000.0) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + 1000.0", [TEST_HUMAN_ID]);

    const correlationId = "futures-list-" + Date.now();
    const res = await createFuturesListing(repo, {
      sellerId: TEST_HUMAN_ID,
      commodity: "energy",
      size: 50,
      strikePrice: 2.50,
      durationGameMinutes: 14550,
      correlationId,
    });

    assert.equal(res.ok, true);
    assert.ok(res.contractId);
    placedContractId = res.contractId;

    // Cancel listing
    const cancelRes = await cancelFuturesListing(repo, {
      sellerId: TEST_HUMAN_ID,
      contractId: placedContractId,
    });
    assert.equal(cancelRes.ok, true);
    placedContractId = "";
  });
});
