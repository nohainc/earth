# EARTH PostgreSQL migration status

This document records the safe migration boundary for the current EARTH game.
PostgreSQL is the live gameplay authority. The former Cloudflare D1 database
was removed only after parity verification, a rollback rehearsal, and a
successful D1-free production deployment.

## Current architecture

- Flutter Web client: `flutter_client/`
- Cloudflare Worker API and edge event endpoints: `cloudflare/src/index.ts`
- Current live authority: PlanetScale PostgreSQL through Hyperdrive binding `HYPERDRIVE`
- Retired authority: Cloudflare D1 database `earth-world` (deleted after cutover)
- Coordination only: Durable Object `MARKET_COORDINATOR`
- Side effects: email binding and future outbox/queue processing

The Hyperdrive connection is configured as `planetscale-earth-main-2eh5` and
is verified by `/api/health` as the authoritative gameplay store.
The repository boundary fails closed if the PostgreSQL authority flag or
Hyperdrive binding is missing; it cannot silently fall back to the deleted D1
database.

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
2. Add and continuously verify `db/schema-manifest.json` with expected tables,
   columns, unique constraints, and indexes. CI and the release checklist run
   `npm run db:verify:manifest` before PostgreSQL is treated as deployable.
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

## Cutover result

The connection, schema, initial data, rollback rehearsal, and economic
invariant gates passed. Production was deployed with PostgreSQL authority, the
D1 binding was removed, and the remote `earth-world` D1 database was deleted.
The repository tools are `npm run db:migrate:postgres`,
`npm run db:import:d1`, `npm run db:verify:d1-postgres`, and
`npm run db:test:restore`; all require explicit credentials and never use the
Worker Hyperdrive binding implicitly.
