# EARTH PostgreSQL migration status

This document records the safe migration boundary for the current EARTH game.
The live gameplay authority remains D1 until every PostgreSQL migration gate is
green. No production schema reset or destructive copy is permitted.

## Current architecture

- Flutter Web client: `flutter_client/`
- Cloudflare Worker API and edge event endpoints: `cloudflare/src/index.ts`
- Current live authority: Cloudflare D1 binding `DB`
- Target authority: PlanetScale PostgreSQL through Hyperdrive binding `HYPERDRIVE`
- Coordination only: Durable Object `MARKET_COORDINATOR`
- Side effects: email binding and future outbox/queue processing

The Hyperdrive connection is configured as `planetscale-earth-main-2eh5` and
is verified by `/api/health` without changing gameplay reads or writes.

## Feature audit

| Area | Worker/API coverage | PostgreSQL migration gate |
| --- | --- | --- |
| Identity, sessions, verification, recovery, MFA, rate limits | Implemented | Password/session tables copied and hash/token behavior verified |
| World clock, lifecycle, succession, inheritance, estate liquidation | Implemented | Transactional day advancement and ownership invariants |
| Market book, reservations, settlement, fees, ledger | Implemented | Serializable settlement transaction and idempotency replay |
| Communities, cities, corporations, budgets, representation | Implemented | Foreign keys, balance constraints, event history parity |
| Governance, roles, delegation, proposals, ballots, arbitration | Implemented | Unique ballot/idempotency constraints and append-only events |
| Production, machines, maintenance, upgrades, recycling, sales | Implemented | Asset ownership and accounting transaction parity |
| Research, patents, licenses, royalties | Implemented | License uniqueness and ledger correlation parity |
| Personal finance, taxation, liquidity, recovery | Implemented | Numeric precision and non-negative balance invariants |
| Businesses, shares, constitutions, managers, statements, taxes | Implemented | Share ownership and financial statement reconciliation |
| AI assistants and service effects | Implemented | Policy/authority boundaries and cost ledger parity |
| Notifications, audit, activity, SSE/WebSocket | Implemented | Read-model rebuild and event ordering verification |
| Landing page and Flutter `/app` shell | Implemented | Independent of persistence cutover |

## Required migration gates

1. Translate all 50 D1 migrations into reviewed PostgreSQL migrations. Preserve
   the existing identifiers, correlation IDs, and game-day semantics.
2. Add a schema manifest with expected tables, columns, unique constraints, and
   indexes. The Worker must report parity before PostgreSQL becomes authoritative.
3. Copy data in dependency order using checksums and row counts. Do not mutate
   D1 during the first verification pass.
4. Introduce repository boundaries for reads, writes, transactions, and batch
   operations. Keep provider-specific SQL inside the adapter.
5. Verify invariants: credits conserved, balances non-negative, ledger entries
   balanced, ownership unique, machine condition bounded, and all mutations
   idempotent under replay.
6. Run shadow reads and compare normalized snapshots for at least one complete
   game-day cycle.
7. Enable PostgreSQL authority behind an explicit Worker environment flag, then
   retain a monitored rollback window without destructive cleanup.

## Guide-aligned implementation rules

- Use PostgreSQL transactions for economic mutations; never emulate a
  multi-table transaction with independent requests.
- Use numeric PostgreSQL types for credits and quantities; do not use floating
  point for authoritative money.
- Use append-only ledger and ownership events with correlation IDs.
- Use deterministic game-clock inputs and idempotency keys for scheduled work.
- Keep Durable Objects for coordination and WebSockets, not authoritative
  economic state.
- Validate API payloads at the boundary and keep Flutter models generated from
  the versioned API contract as the client surface grows.

## Current decision

The connection, schema, and initial data gates are green: the reviewed schema
is applied, the D1 export has been imported, and row counts plus core economic
invariants reconcile. D1 remains authoritative until the Worker persistence
coupling is refactored behind a PostgreSQL transaction repository and shadow
reads have passed for a complete game-day cycle. The repository tools are
`npm run db:migrate:postgres`, `npm run db:import:d1`, and
`npm run db:verify:d1-postgres`; all require explicit credentials and never use
the Worker Hyperdrive binding implicitly.
