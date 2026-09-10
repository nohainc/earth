# Economy V2 — Plan 0: Isolation and Dependency Boundary

Status: inventory complete; no destructive cutover performed.

This document establishes the boundary for Economy V2. The existing EARTH
gameplay and coordination systems remain in place while the accounting
infrastructure is replaced incrementally.

## Non-negotiable preservation boundary

The following remain part of the active game domain and settlement
coordination layer:

- identity, authentication, owner registry, houses, lineage, and life systems;
- cities, corporations, institutions, communities, memberships, governance,
  buildings, research, technologies, and scheduled actions;
- markets, futures, banking, taxes, budgets, financial states, dividends,
  rankings, snapshots, world state, events, notifications, AI, and error
  observability;
- `daily_settlement_runs`, `daily_settlement_control`,
  `daily_settlement_phase_runs`, `settlement_anomalies`, and
  `entity_end_of_day_snapshots`.

These systems may be adapted to emit or consume V2 economic postings, but they
are not Plan 0 deletion targets.

## Temporary legacy accounting boundary

The following objects are retained during migration and are the replacement
boundary, not the initial deletion set:

- `account_balances`
- `resource_balances`
- `ledger_entries`
- `resource_ledger_entries`
- `daily_settlement_profiles`
- `daily_settlement_profile_runs`
- `resource_rate_history`

The first four are the legacy balance and audit stores. The settlement profile
concept is retained because it provides a useful prepared-delta boundary; its
per-owner rebuild and catch-up implementation will be replaced by set-based
calculation, effect generation, netting, and bulk posting.

## Function disposition

| Function | Plan 0 disposition |
| --- | --- |
| `earth_get_current_game_time()` | Keep; core world-clock primitive |
| `earth_record_rate_change()` | Keep temporarily; redesign with the V2 rate-segment model later |
| `earth_transfer_credits()` | Keep temporarily; replace after all callers use V2 posting |
| `earth_mutate_resource_balance()` | Keep temporarily; replace after all callers use V2 posting |
| `earth_catchup_owner_settlement()` | Keep temporarily; remove only after bulk settlement is operational |
| `earth_rebuild_settlement_profile()` | Keep temporarily; replace with a bulk/set-based builder |
| `earth_create_market_order()` | Keep the market feature; rewrite its accounting integration |

Bank deposit/withdrawal, market order, and other domain functions are rewrite
candidates, not feature deletion candidates.

## Current dependency inventory

The inventory below covers production application code and database function
definitions. Historical migrations are intentionally listed separately: they
are append-only history and must not be edited or selectively deleted.

| Legacy object | Application callers | Main production areas |
| --- | ---: | --- |
| `account_balances` | 20+ files | scheduler, finance, market, institutions, banking, buildings, lifecycle, API/read models |
| `resource_balances` | 10+ files | resource ledger, scheduler, market, real estate, lifecycle, finance |
| `ledger_entries` | 20+ files | transfers, finance, market, banking, scheduler, snapshots, integrity/read models |
| `resource_ledger_entries` | 4+ files | resource mutation, settlement, resource-ledger reads |
| `daily_settlement_profiles` | 4+ files | profile service, scheduler, finance route, building settlement |
| `daily_settlement_profile_runs` | function/migration focused | settlement catch-up and idempotency history |
| `resource_rate_history` | rate/settlement focused | rate-change function and resource settlement |

The current TypeScript settlement path is explicitly per-owner:

1. `rebuildDirtyDailySettlementProfiles()` locks dirty profiles and calls the
   stored profile builder once per owner.
2. `applyPreparedSettlementProfiles()` selects due owners and calls
   `earth_catchup_owner_settlement()` once per owner.
3. The scheduler executes these phases inside the broader scheduler transaction.

This is the first implementation boundary to replace after V2 posting and
effect netting exist. It is not removed in Plan 0.

## Schema-source drift

`db/schema-manifest.json` declares migration version 149, while the header in
`db/schema.sql` says the clean schema is only through migration 080. The
numbered migration history is authoritative for the applied database, so the
canonical fresh-install schema must be reconciled before V2 becomes the
canonical implementation.

Until that reconciliation is complete:

- do not describe `db/schema.sql` as a migration-149 fresh-install schema;
- do not reset a shared or local test database as part of Economy V2 work;
- do not alter historical migrations 001–149;
- use the manifest and live migration state together when validating schema
  readiness.

## Cutover gates

The legacy objects may be removed only after all of these are true:

1. V2 accounts and posting primitives are installed alongside the legacy
   tables.
2. Interactive domains have migrated their balance mutations to V2.
3. Daily engines generate effects and the settlement coordinator bulk-posts
   netted effects idempotently.
4. Repository search and database catalog checks show no production callers of
   the legacy balance/ledger primitives.
5. Integrity checks cover missing owners, duplicate default accounts, invalid
   assets, negative balances, unbalanced transactions, and transactions with
   no entries.
6. Seeds, fresh-install schema, manifest, regression fixtures, and operational
   diagnostics pass against the V2 path.

Only then should the final forward migration remove the superseded accounting
objects, including `daily_settlement_profile_runs` if its audit replacement is
complete.
