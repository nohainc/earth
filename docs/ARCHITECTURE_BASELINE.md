# EARTH Architecture Freeze — V2 Baseline

> Baseline date: 2026-09-11  
> Repository: `earth`  
> Purpose: freeze the current architecture before further cleanup work.

## Authoritative systems

| System | Current authority | Boundary |
|---|---|---|
| House | `houses` and `house_affiliations` | Persistent player and institutional affiliation |
| Human | `humans` | Mortal representative, personal standing and offices |
| Economy V2 | `economic_accounts`, `economic_transactions`, `economic_entries` | Money/resource balances and ledger postings |
| Building V2 | Building V2 planner/journal and catalog rules | Production, upkeep and services |
| Market V2 | Spot instruments, orders, batches, fills and V2 escrow | Spot trading only |
| Finance V2 | Finance contracts and projections | Banking, tax, obligations and financial state |
| Technology/IP V2 | Technology catalog, access, patents and licenses | Corporation research and technology rights |
| Cities | `cities` plus V2 institutional accounts | Public institutions and service consumers |
| Corporations | `corporations` plus V2 institutional accounts | Corporate institutions and research actors |
| Budgets V2 | `institution_budget_lines` and commitments | Spending authorization, not money |
| Proposal/Governance V2 | Proposal state machine, ballots, roles and actions | Decisions and authority |
| Scheduler V2 | Worker scheduled handler plus PostgreSQL settlement runs | Game-time progression and ordered phases |

PostgreSQL is the sole canonical persistence authority. Cloudflare Worker
modules calculate, authorize and orchestrate; Durable Objects only coordinate
live delivery; transactional outbox delivery is post-commit.

## Database baseline

- Migration head: `001_baseline.sql`.
- Canonical fresh-install schema: `db/baseline/`, assembled by
  `db/migrations/001_baseline.sql`.
- Schema manifest: `db/schema-manifest.json`, `migrationVersion: 1`.
- Production-compatible scheduled entry point: `cloudflare/src/index.ts`.
- Production cron configuration: `wrangler.api.jsonc`, `* * * * *`.
- Economy V2 is still in migration/shadow-reconciliation mode; legacy callers
  remain known debt and must not be mistaken for final authority.

## Known legacy and transitional inventory

### Legacy tables or models still present for migration/compatibility

- `account_balances`, `resource_balances`, `ledger_entries` and
  `resource_ledger_entries`.
- Legacy profile/rate functions, including
  `earth_catchup_owner_settlement` and `resource_rate_history`.
- Legacy human-bound lifecycle, membership and finance compatibility paths.
- Deprecated scalar/read projections where explicitly documented by their
  migrations.
- Historical business and old domain tables retained only where a later
  migration has not yet removed them.

The obsolete continuous simulation orchestrator, one-fill market engine and
V1 building settlement engine have been removed. Market clearing is owned by
the batch scheduler and building settlement by Building V2.

### Legacy or compatibility APIs/adapters

- `transferCredits()` and `mutateResourceBalance()` adapters in modules that
  have not completed the Economy V2 cutover.
- Legacy one-at-a-time profile settlement adapters.
- Compatibility membership projections between Human memberships and House
  affiliations.
- `server.js` local reference simulator/compatibility harness; it is not a
  production authority.

### Legacy scheduler/deployment debt

- `scheduler-postgres.ts` still contains compatibility and older inline paths
  alongside the resumable V2 phase registry.
- `scripts/recalculate-profiles.mjs` still invokes the legacy owner catch-up
  function.
- The full production test command includes localhost integration/browser
  checks that require a permitted local server and configured services.

### Deprecated or deferred models

- Old budgets model: retired by migration 316; current code uses budget lines.
- Scalar city/corporation treasury columns: removed from the canonical schema;
  migration history documents the former compatibility projection.
- City capacity scalars: retained as compatibility/read fields while
  `city_service_capacity_daily` is the V2 projection.
- Hono, Zod, Drizzle, Queues, R2 and microservice decomposition: deferred and
  require a new ADR before adoption.

### Feature flags and runtime modes

- Production feature flags are resolved centrally by
  `cloudflare/src/feature-config.ts`. Supported flags are
  `FEATURE_SPOT_MARKET`, `FEATURE_BANK_DEPOSITS`, `FEATURE_BANK_LOANS`,
  `FEATURE_PATENTS`, `FEATURE_TECH_LICENSES`,
  `FEATURE_MORTALITY`, `FEATURE_FORCED_LIQUIDATION` and
  `FEATURE_INSTITUTION_DISTRESS`, `FEATURE_COMMUNITIES`. Server mutation routes reject disabled features and
  scheduled processors skip their disabled work.
- `/api/health` exposes the internal world-health read model: settlement
  phase/lease/progress, backlog and failed runs, entity counts, market work,
  database connections, slow-query count, API/Worker errors and outbox state.
  PostgreSQL optional observability views are best-effort and never make the
  health endpoint fail when an extension is unavailable.
- Scheduler catch-up is controlled by `EARTH_SCHEDULER_MAX_CATCHUP_DAYS` and
  `EARTH_SCHEDULER_WORK_BUDGET_MS`.
- Local launcher modes are `EARTH_LOCAL_MODE=live|manual|ui`.
- Remote database mutation from the local scheduler requires the explicit
  `EARTH_ALLOW_REMOTE_MUTATION=true` override.
- Economy V2 shadow reconciliation remains an active migration gate.

### Progressive advanced-feature activation

Closed-beta rollout may cap the central feature registry with
`EARTH_FEATURE_ACTIVATION_STAGE`. The stages are cumulative and ordered:

1. `baseline` — spot market and deposits only;
2. `bank_loans`;
3. `mortality`;
4. `patents`;
5. `technology_licensing`;
6. `institution_distress`;
7. `forced_liquidation`.

The default `all` stage preserves the current development configuration. For
closed beta, enable one stage, observe several accelerated game years with the
closed-beta soak harness, review the world-health and reconciliation signals,
then advance to the next stage. An activation stage is a server-side cap:
client/API requests cannot enable a feature beyond it, and scheduled work is
skipped for capped features.

## Baseline test record

### Passing deterministic baseline

Command:

```text
node --experimental-strip-types --test \
  test/institution-budget-v2.acceptance.test.mjs \
  test/institution-budget-cutover.test.mjs \
  test/institution-budget-concurrency.test.mjs \
  test/institution-budget-scale.test.mjs \
  test/institution-budget-scenarios.test.mjs \
  test/institution-authorization.test.mjs \
  test/institution-treasury-authority.test.mjs \
  test/house-affiliations-authority.test.mjs \
  test/house-population-projections.test.mjs \
  test/city-service-capacity-projection.test.mjs \
  test/institution-financial-events.test.mjs \
  test/corporation-distress-liquidation.test.mjs
```

Result on the baseline checkout: **36 tests passed, 0 failed**. `git diff
--check` passed.

### Full project test command

`npm test` was attempted. Its deterministic portions ran, but the command
failed in the restricted execution environment because HTTP/browser tests
could not bind or connect to localhost (`EPERM`, including ports 8995–9015).
Those failures are environment/setup failures, not recorded as passing tests.
Run `npm test` again on a host with the local services and browser test
permissions enabled before treating the full suite as a release result.

## Freeze rules

1. New gameplay systems must use the authoritative systems in the table above.
2. New code must not add references to retired V1 models.
3. Compatibility adapters may be removed only after repository-wide dependency
   checks and reconciliation tests pass.
4. Any change to an authority boundary, migration head, or scheduler phase
   ordering requires updating this baseline or creating a superseding ADR.
