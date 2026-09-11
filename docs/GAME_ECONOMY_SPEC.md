# EARTH Game Economy Specification

This specification turns the Constitution into a shared operational model.
Balance, rate, cost, and capacity values remain versioned data so a historical
settlement can always use the rules that were effective on its game day.

## Time and settlement

- One game day is 1,440 game minutes.
- One real minute advances 60 game minutes.
- One game day is 24 real minutes.
- PostgreSQL is the authoritative game clock.
- Daily economic settlement runs once per complete game day.
- Human needs, taxes, bank settlement, research capacity, and recurring
  licenses are daily calculations.
- Fiscal months, quarters, and years are planning/reporting periods only; they
  do not replace or alter daily cash-flow semantics.
- Scheduler retries and catch-up process complete game days in strict order.

## Daily Economy Contract

The game day is the fundamental economic accounting period. Every authoritative
economic result is calculated for a complete game day and is identified with
that `game_day` in its settlement, journal, or contract record. The daily
contract covers, at minimum:

| Domain | Fundamental unit |
|---|---|
| Building production and operating expense | per game day |
| Service capacity and service revenue | per game day |
| Human needs and life maintenance | per game day |
| Tax assessment and payment attempts | per game day |
| Bank interest accrual and scheduled payments | per game day |
| Research capacity and progress | per game day |
| Technology license fees | per game day |
| City service capacity | per game day |
| Institutional commitments and automatic payments | per game day |

Fiscal months, quarters, and years are projections over daily results. A
period projection is calculated as the sum of its daily facts; it is never a
replacement calculation such as `monthlyIncome / days` or `annualCost / days`.
Those periods may authorize or forecast spending, but they do not alter the
underlying daily cash-flow semantics.

Authoritative fields whose cadence could otherwise be ambiguous must use an
explicit daily name such as `daily_output_units`,
`daily_operating_credit_units`, `daily_service_capacity_units`,
`daily_license_fee_units`, or `daily_research_capacity_units`. Generic
`cost`, `income`, and `expense` names are acceptable only when the surrounding
schema makes the daily period unambiguous. Monthly and annual values belong in
read/reporting projections and must not be consumed as settlement inputs.

## Assets and fixed-point units

| Asset | Atomic scale | Display decimals |
|---|---:|---:|
| CREDIT | 100 | 2 |
| MATERIAL | 1,000,000 | 6 |
| COMPONENTS | 1,000,000 | 6 |
| ENERGY | 1,000,000 | 6 |
| COMPUTE | 1,000,000 | 6 |
| FOOD | 1,000,000 | 6 |

Economic settlement uses signed BIGINT atomic units. Display conversion occurs
only at API/UI boundaries. Ratios use integer PPM/BPS representations where
possible.

## Accounting model

Every authoritative value movement is an Economy V2 transaction with balanced
entries per asset. Interactive operations use `earth_post_transaction()`;
aggregated daily work uses `earth_post_settlement_batch()`.

- Normal accounts may not become negative.
- Escrow is a real account, not an order-row promise.
- Internal transfers change account composition, not total supply.
- Production and consumption use explicit source/sink accounts or named
  counterparties.
- CREDIT supply is issuance minus retirement and must reconcile to normal
  account balances, including escrow and reserves as defined by the supply
  projection.

## Economic owners

The canonical private owner is a House. Cities and Corporations own their own
institutional accounts, normally including TREASURY, OPERATIONS, and RESERVE.
Budgets and projections describe authority or analysis; they do not replace
accounts.

## Market

The Spot Market trades MATERIAL, COMPONENTS, ENERGY, COMPUTE, and FOOD against
CREDIT. Orders become eligible according to their immutable batch cutoff.
Clearing is deterministic: price, then database sequence priority, with
self-trade prevention. A completed batch atomically records fills, order
updates, escrow consumption/refunds, and Economy V2 postings.

## Buildings and services

Building settlement is set-based by economic-owner shard:

1. Resolve the catalog/rule version for the day.
2. Snapshot owner inputs and allocate shared resources deterministically.
3. Calculate utilization, physical consumption, and physical production.
4. Calculate service capacity and match customer/public demand.
5. Resolve explicit operating expenses.
6. Compile and validate one economic effect batch.
7. Post atomically, then update building state and audit journals.

Customer-funded service revenue is a transfer from the customer. Public service
revenue has an explicit public payer. A building catalog entry alone never
creates CREDIT.

## Finance and fiscal policy

Taxes create obligations before payments are attempted. Bank interest accrues
as a claim and moves CREDIT only when paid. Deposits are liabilities backed by
real reserve transfers; loans are assets funded by real bank liquidity.

Budget authorization and commitments do not move CREDIT. Actual spending,
grants, reserve transfers, and dividends do. Mandatory obligations are
resolved before discretionary spending and dividend eligibility.

## Research, technology, and IP

Research capacity is a derived institutional capability, not a tradable asset.
Technology definitions, effects, patents, and licenses are versioned. A
technology or access change completed during Day N becomes usable from Day N+1
unless an explicit rule says otherwise. Modifiers stack deterministically and
respect configured caps.

## Human needs and succession

Humans generate aggregate daily demand for food, housing, energy, healthcare,
and connectivity. Buildings and Cities satisfy that demand through capacity and
services; players are not required to perform a separate manual purchase for
each need.

Death is resolved after the day's economic obligations and life calculation.
The successor represents the same House from the next game day. Economic
accounts, buildings, Spot orders/escrow, bank contracts, debts, and House
affiliations do not move during succession.

## Determinism and recovery

All daily rules select immutable versions by game day. Correlation IDs are
database-enforced idempotency keys. Settlement phases and market batches use
leases, barriers, and resumable commits. A retry may resume work, but may not
duplicate an economic result.
