# EARTH — Current Project State

> Last updated: 2026-08-29 · Read this file first in every AI session before opening any other file.

---

## ✅ In Production (live on PlanetScale PostgreSQL + Cloudflare Workers)

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
- AI assistants: list, policy, tier upgrade (rule-based heuristics — **not an LLM**)
- Notifications, audit log, SSE / WebSocket event fan-out
- Daily briefing, net-worth history, market OHLC, futures/derivatives
- Transactional outbox delivery (emails via Cloudflare Email Service)
- Flutter Web client fully functional at `/app`
- 70 forward-only PostgreSQL migrations applied and verified

---

## 🔄 In Progress / Active Debt

- **`index.ts` route extraction** — 2,371 lines; route groups for AI, house, read-models extracted (2026-08-29); communities, corporations, cities, finance, contracts, governance, market, lifecycle still in index.ts
- **`scheduler-postgres.ts`** (671 lines) — contains long inline SQL; `settleBusinessDepreciation` is dead code (empty function, legacy retirement)
- **`ai-postgres.ts`** (46 lines) — AI advisor is rule-based only; hardcoded upgrade cost `2400` not loaded from `world_rules`
- **`objectives.ts`** — all target thresholds (`100000`, `50000`, `25`, etc.) hardcoded; should be loaded from `world_rules` table
- **`decision-queue.ts`** — `gameDay ?? 184` magic default; no player feedback loop or confidence signalling

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

**Authority rule**: PostgreSQL is the only authoritative store. Flutter is untrusted presentation shell. All money/ownership/governance mutations go through PostgreSQL transactions with `transferCredits()`.

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
- Run: `npm run qa:<feature>` or `npm test`
- Flutter: `npm run flutter:test` (172 tests pass)
- DB invariants: `npm run db:verify:invariants` (requires `DATABASE_URL`)
