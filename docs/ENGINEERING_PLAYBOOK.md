# EARTH engineering playbook

This is the project-owned implementation guide for future human and AI
contributors. It supplements the original EARTH engineering guide and is
intentionally practical for the current codebase.

## Architecture

EARTH uses a functional core and imperative shell:

```text
Flutter client
  -> API route / command handler
  -> authentication and authorization
  -> pure domain rule functions
  -> repository interface
  -> PostgreSQL transaction through Hyperdrive
  -> append-only ledger/events
  -> async notifications and Durable Object broadcasts
```

The domain and application layers must not import Cloudflare bindings. Cloudflare
bindings belong in infrastructure adapters. Durable Objects coordinate live
events and market presence; they do not own authoritative economic state.

## Vertical slices

Build one complete feature at a time:

1. PostgreSQL migration and constraints.
2. Domain model and pure rule functions.
3. Command/query contract.
4. Authorization policy.
5. Repository interface and PostgreSQL implementation.
6. Worker route and canonical response.
7. Flutter repository, model, view-model, and screen.
8. Unit, transaction, replay, parity, and production smoke tests.

Do not create broad database-only or UI-only batches. A slice is complete only
when the user-visible behavior, authoritative transaction, and verification are
complete.

## Commands, queries, and events

- Commands mutate state: `PlaceMarketOrder`, `SettleMarket`, `SettleTax`,
  `AcceptContract`, `DeclareInsolvency`.
- Queries read state: `GetMarketBook`, `GetPersonalFinance`, `GetBusiness`.
- Events notify consumers after commit: ledger events, world events,
  notifications, and Durable Object broadcasts.

Commands must authenticate, authorize, load rule state, validate invariants,
execute one transaction, append audit/ledger records, commit, then emit events.
Never broadcast an event before the transaction commits.

## Result-oriented business failures

Expected game outcomes should be returned as typed results or stable API error
codes (`INSUFFICIENT_FUNDS`, `INVALID_PRODUCT`, `NOT_ELIGIBLE`,
`ALREADY_PROCESSED`). Exceptions are reserved for infrastructure failures and
unexpected defects. Routes translate domain results into HTTP responses; domain
code must not know HTTP status codes.

## Explicit invariants

Every economic command must preserve these invariants:

- account balances never become negative;
- every credit movement has a positive ledger amount and correlation ID;
- a settlement correlation cannot be applied twice;
- ownership changes and asset links change atomically;
- machine condition stays in `[0, 100]`;
- market reservations are released or consumed exactly once;
- business profit equals revenue minus operating costs;
- game-day inputs are explicit and deterministic.

Prefer named pure functions such as `calculateTax`, `calculateProduction`,
`calculateMachineWear`, and `calculateMarketAllocation`. Test them without a
database, then test the repository transaction separately.

## Persistence rules

- PostgreSQL is the target authority and D1 is the controlled fallback during
  migration only.
- Provider-specific SQL lives in `cloudflare/src/*-postgres.ts` adapters.
- Multi-table economic changes use one PostgreSQL transaction and row locks
  where concurrent commands can compete.
- Use `numeric` for authoritative credits and quantities.
- Use stable idempotency/correlation keys and append-only ledger/history rows.
- Do not add direct `env.DB` access to a newly migrated feature.
- New migrated features must expose `persistence: 'planetscale-postgres'` when
  the PostgreSQL authority flag is enabled.

## Verification gates

For every slice, run:

1. pure domain tests;
2. repository transaction tests, including rollback and replay;
3. D1/PostgreSQL normalized parity checks;
4. `npm test` and `npm run cf:check`;
5. production smoke test and `/api/health` shadow parity;
6. one monitored game-day before promoting authority.

The authority flag remains `d1` until all economic commands in the current
slice have passed these gates. Never switch only one side of a multi-command
domain without recording the boundary.

## Current migration inventory

PostgreSQL transaction slices currently implemented behind the flag:

- market order submission and settlement;
- OUC public spending;
- tax settlement;
- personal insolvency and liquidation;
- expired-estate liquidation;
- contract acceptance.
- contract arbitration and refunds;
- business creation with shares, constitution, management, and financials.
- machine acquisition, maintenance, and utilization updates.

Still required before global authority promotion:

- business share transfers, constitutions, management, and financial statement
  writes;
- production settlement, machine upgrades, recycling, and machine sales;
- succession inheritance;
- governance, research, licensing, and scheduled world advancement.

### Migration boundary rule

The PostgreSQL path is intentionally dormant while `PERSISTENCE_AUTHORITY=d1`.
Production machine routes must be tested through the same repository contract
before the flag changes. A route is not considered migrated merely because its
schema exists or its read path is shadowed: every state-changing branch must
have an idempotent PostgreSQL transaction, stable error behavior, and a
rollback/replay test. The current machine boundary covers acquisition,
maintenance, and utilization; upgrade, recycling, sales, and scheduled
production remain separate slices.
