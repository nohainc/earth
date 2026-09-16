# EARTH — Current Project State

> Last updated: 2026-09-16 · Development baseline: see `ARCHITECTURE_BASELINE.md`.

---

## ✅ Implemented in the current codebase

- Identity, sessions, MFA, rate limiting, email verification, account recovery
- World clock, lifecycle, succession, inheritance, estate liquidation
- Market book, batch-auction settlement, escrow, fees, ledger
- Communities, cities, corporations — budgets, membership, representation
- Governance: proposals, ballots, roles, delegation, appeals, arbitration
- Production: machines, maintenance, upgrades, recycling, building construction
- Research, patents, licenses, royalties
- Personal finance, taxation, liquidity, insolvency restructuring
- Businesses: shares, constitutions, managers, statements, dividends, mergers
- Contracts: employment, supply, intellectual-service, disputes
- House/dynasty: lineage, perks, heirlooms, succession
- Notifications, audit log, SSE / WebSocket event fan-out
- Daily Summary, net-worth history, market OHLC
- Transactional outbox delivery (emails via Cloudflare Email Service)
- Flutter Web client fully functional at `/app`
- Migration head 78; local canonical schema and manifest are reconciled through
  migration 78. Production deployment still requires the remote database,
  readiness, canary, and rollback gates described in `RELEASE_REHEARSAL.md`.

---

## 🔄 In Progress / Active Debt

- **`index.ts` route extraction** — 2,371 lines; route groups for AI, house, read-models extracted (2026-08-29); communities, corporations, cities, finance, contracts, governance, market, lifecycle still in index.ts
- **`scheduler-postgres.ts`** — contains long inline SQL; resumable V2 settlement now provisions future entry partitions before daily work
- **`objectives.ts`** — all target thresholds (`100000`, `50000`, `25`, etc.) hardcoded; should be loaded from `world_rules` table
- **Economy V2 archival** — the current cutover verifier reports no legacy
  production callers; archival/removal remains a separate reviewed forward
  migration and is not performed automatically.

---

## ⏸️ Deferred (require new ADR before adoption)

- Hono router
- Zod validation
- Drizzle ORM
- Riverpod code generation (Flutter)
- OpenAPI-generated Dart clients
- Cloudflare Queues
- Cloudflare R2
- Microservices split

---

## 🏗️ Architecture Quick Reference

```
Flutter Web → Cloudflare Worker (cloudflare/src/index.ts)
           → *-postgres.ts domain modules
           → PostgreSQL via Hyperdrive (PlanetScale)
           → MarketCoordinator Durable Object (WebSocket fan-out only — no state)
```

**Authority rule**: PostgreSQL is the only authoritative store. Flutter is an
untrusted presentation shell. Economy V2 ledger tables and projections are the
active runtime authority; retired legacy accounting paths are not release
dependencies.

---

## 📁 Key Files for AI Sessions

| Task | Read first |
|---|---|
| Add API route | `AI_FILE_MAP.md` → matching `*-routes.ts` → `*-postgres.ts` |
| Fix simulation | `scheduler-postgres.ts` → relevant `engines/*.ts` |
| Add migration | `db/migrations/` → `db/schema-manifest.json` |
| Flutter change | `flutter_client/lib/features/<domain>/` → `core/api/` |
| AI advisor | `ai-postgres.ts` + `decision-queue.ts` + `objectives.ts` |
| Test | `npm run qa:<feature>` (see package.json scripts) |

---

## 🧪 Test Gate

- 80% line coverage required before merge (documented; not yet CI-enforced)
- `npm run db:verify:canonical` checks the fresh-install schema against the manifest and migration head
- Run: `npm run qa:<feature>` or `npm test`
- Flutter: `npm run test:flutter:v4` (59 maintained V4 tests pass)
- DB invariants: `npm run db:verify:invariants` (requires `DATABASE_URL`)
