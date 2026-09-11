# EARTH Market V2

## Accounting boundary

> **Orders and fills describe trading intent and execution; Economy V2 escrow and ledger entries are the only authoritative representation of value.**

`market_orders`, `market_fills`, batches, candles, and instrument state are market records or rebuildable read models. They must never become a second balance system. Every reservation, release, spot delivery, fee, and refund must be posted through Economy V2.

## Architecture

The market currently supports spot instruments through one instrument catalog, order contract, escrow service, immutable clearing batches, deterministic clearing engine, fill history, idempotency keys, and scheduler leases. Spot fills exchange the base and quote assets immediately.

## Acceptance checklist

The implementation is complete only when the following are true:

- Economy V2 is the only balance authority; no market path mutates legacy balances.
- Every open order has matching Economy V2 collateral.
- Reservations remain conserved and are released or consumed exactly once.
- Orders have immutable batch eligibility and deterministic price/sequence priority.
- Historical catch-up cannot include orders submitted after a batch cutoff.
- Self-trades cannot block clearing.
- A batch supports many fills while posting aggregated, set-based economic effects.
- Every fill identifies both orders and its Economy V2 transaction.
- Fee and rule terms are snapshotted at acceptance.
- Spot settlement is immediate.
- Retries cannot duplicate fills, postings, or cancellations.
- Supply/demand state and candles can be rebuilt from authoritative market records.
- Integrity reports detect collateral, fill, batch, and conservation violations.
- Deterministic fuzz, crash/concurrency, and target-scale benchmark suites pass their required budgets.

## Read model rule

Instrument state, order-book summaries, candles, and API display values are projections. They may be refreshed or rebuilt from orders, fills, batches, and Economy V2 records. They must not be used to authorize value movement or replace escrow/account checks.
