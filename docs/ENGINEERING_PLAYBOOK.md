# EARTH engineering playbook

This is the project-owned implementation guide for future human and AI
contributors. It supplements the original EARTH engineering guide and is
intentionally practical for the current codebase.

The detailed system-boundary and database responsibility contract is maintained
in [`ARCHITECTURE.md`](./ARCHITECTURE.md). When this playbook and that contract
appear to conflict, resolve the difference explicitly in a new migration or
architecture decision before implementing the slice.

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

The client uses one coherent futuristic visual system for the current release;
theme preferences are intentionally deferred so gameplay information hierarchy
and accessibility remain consistent across Humans.

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

## API error contract

Every JSON error crossing the Worker boundary includes:

- `error`: a safe, human-readable message;
- `code`: a stable machine-readable category such as
  `AUTHENTICATION_REQUIRED`, `VALIDATION_ERROR`, `CONFLICT`, or
  `SERVICE_UNAVAILABLE`;
- `correlationId`: the request identifier used to locate the structured Worker
  log for the failure.

Provider messages, SQL text, stack traces, credentials, and recipient data do
not cross the API boundary. Infrastructure failures are logged as structured
events with an internal diagnostic message and returned to the client using a
safe service-level code.

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

- PostgreSQL is the live authority. Cloudflare D1 was a migration-only store
  and has been removed; new code must not add D1 access.
- Persistence configuration must fail closed when PostgreSQL authority or the
  Hyperdrive binding is absent; never restore a deleted-provider fallback.
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
3. `npm test`, `npm run cf:assert-postgres`, and `npm run cf:check`;
4. production smoke test and `/api/health` persistence/readiness checks;
5. one monitored game-day after each scheduled-simulation change.

The deterministic local simulator can be exercised across several world sizes
and horizons with `npm run simulate:scenarios`. It fails when credit,
resource, institution, or machine-condition invariants are violated.

Run `npm run audit:mutation-boundaries` to verify that PostgreSQL mutation
adapters retain transaction boundaries, visible replay/correlation handling,
the PostgreSQL authority guard, and no legacy D1 access.

The authority flag is `postgres` after the completed cutover. Never switch only
one side of a multi-command domain without recording the boundary.

## Change and release procedure

Use this order for every production change. Keep the change within one
vertical slice when possible.

### Flutter UI changes

1. Edit `flutter_client/lib/main.dart` or the relevant Flutter feature files.
2. Keep API calls in the client API/repository layer; do not put PostgreSQL or
   Cloudflare logic in widgets.
3. Add or update a widget test for the visible state and a client-side loading,
   empty, success, and error state where applicable.
4. Run `flutter analyze`, `flutter test`, and
   `flutter build web --release --dart-define=EARTH_API_URL=https://earthuc.com`,
   followed by `npm run flutter:prepare:web`.
5. Deploy the generated `flutter_client/build/web` assets together with the
   Worker. If an app-shell change is not visible on the custom domain, check
   the Worker custom-domain target and the `WEB_ASSET_VERSION` cache key before
   changing application logic.

### Worker/API changes

1. Add the route at the Worker boundary and keep the response contract stable.
2. Put authorization before loading private state; use the authenticated
   Human ID from the server session, never a client-supplied owner ID.
3. Put PostgreSQL state changes in a `*-postgres.ts` adapter and use one
   transaction for related writes. Add idempotency and audit/correlation data.
4. Add route tests plus transaction, rollback, replay, and authorization tests.
5. Run `npm test`, `npm run cf:assert-postgres`, and
   `npm run cf:check -- --env production` before deployment.

### Database changes

1. Read `db/initial.sql` and `db/schema-manifest.json`; do not review historical
   migrations `001–074` unless an investigation specifically needs them. Add
   the next available numbered SQL migration under `db/migrations/` (the
   profile-settlement work begins at `075`).
2. Update `db/schema-manifest.json` when schema or indexes change.
3. Run `npm run db:migrate:postgres` and `npm run db:verify:manifest`.
4. Confirm `/api/health` reports PostgreSQL authority, schema readiness, data
   readiness, non-negative balances, bounded machine conditions, and shadow
   parity.
5. Never reintroduce D1 as a fallback. D1 is deleted and is migration-history
   evidence only.

### Production promotion

1. Review `git diff --check`, run all applicable gates, commit the slice, and
   push the branch.
2. Deploy with `npx wrangler deploy --env production --keep-vars`.
3. Confirm the custom domain `earthuc.com` is attached to
   `earth-api`, using the separated deployment workflow rather than the deleted legacy `earth-world` service.
4. Run `npm run cf:smoke` and verify `/api/health` on `https://earthuc.com`.
5. Test the changed user journey in the browser using the public URL. Record
   the Worker version ID and any migration version in the handoff.

### Authentication-specific checks

- Registration requires display name, email, password, and repeated password.
- Verification-required login errors must expose a resend-verification action.
- Verification and recovery responses remain generic for unknown addresses.
- Verification resend is throttled server-side, sends from the authenticated
  `earth@auth.earthuc.com` domain, and replies to `earth@nohainc.com`.
- Session cookies are issued and cleared only by the Worker; Flutter never
  stores or constructs an authentication token itself.

## Current PostgreSQL inventory

PostgreSQL transaction slices currently live in production:

- market order submission and settlement;
- OUC public spending;
- tax settlement;
- personal insolvency and liquidation;
- expired-estate liquidation;
- contract acceptance;
- contract arbitration and refunds;
- business creation with shares, constitution, management, and financials;
- machine acquisition, maintenance, and utilization updates.
- succession registration and estate inheritance settlement;
- production settlement, machine upgrades, recycling, and machine sales;
- governance, research, licensing, and scheduled world advancement;
- scheduled depreciation, taxation, basic levy, AI maintenance, contract
  completion, financial-state transitions, and ranking snapshots.
- starter-package onboarding with live market, production, governance, and
  Community opportunity signals in the authenticated command center.
- indexed starter packages using the live living-cost and productive-economy
  indices, with bounded reserves shown in the command center.

The remaining entries are feature-completion slices, not persistence-authority
promotion gates.

### Feature boundary rule & 80% Test Coverage

The PostgreSQL path is authoritative while `PERSISTENCE_AUTHORITY=postgres`.
A route is not considered complete merely because its schema exists: every
state-changing branch must have an idempotent PostgreSQL transaction, stable
error behavior, and a rollback/replay test.

**Automated Test Coverage Gate**:
- All code across the repository must maintain **at least 80% automated line test coverage** (`LF`/`LH` $\ge 80.0\%$).
- Any PR or feature slice resulting in aggregate test coverage under 80% is blocked from release until corresponding unit and widget/integration tests are added.

### Simulation Time Scale & Actuarial Mortality Standard
- **Time Dilation Ratio (1:60)**:
  - 1 Real Second = 1 Simulation Game Minute.
  - 60 Real Seconds (1 Real Minute) = 1 Simulation Game Hour.
  - 24 Real Minutes = 1 Simulation Game Day (1,440 Game Minutes).
  - 6 Real Days = 360 Simulation Game Days (1 Game Year).
  - 6.08 Real Days = 365 Simulation Game Days (1 Solar Game Year).
  - A character lifespan of ~60 active simulation years (Age 20 to 80) corresponds to **~365 Real Days (~1 Real Calendar Year)**.
- **Biometric Health & Stochastic Mortality Engine**:
  - Health (0–100%) governs operational labor capacity, machine maintenance speed, and living medical expenses.
  - Mortality is not a simple countdown to 0% health. Citizens can live long lives with chronic or moderate health ratings (30–60%).
  - Mortality past age 65 operates as an actuarial hazard rate roll per annual epoch (Gompertz-Makeham curve), with variance allowing lucky or well-cared-for citizens to live up to 95–100+ simulation years.

Continue adding gameplay features
as vertical slices, with the full route, Flutter surface, and verification
before moving to the next slice.
