# ADR-001: Current architecture boundary

- Status: Accepted
- Date: 2026-08-16
- Owners: EARTH engineering
- Scope: Flutter client, Cloudflare Worker, Durable Objects, PostgreSQL, and
  asynchronous delivery
- Supersedes: none

## Decision summary

EARTH uses an incremental bounded-context modular monolith.

The production system consists of:

1. Flutter Web as an untrusted presentation client.
2. A Cloudflare Worker as the HTTP, authentication, validation, authorization,
   orchestration, and response boundary.
3. TypeScript domain modules for deterministic rules and PostgreSQL command
   adapters.
4. PostgreSQL, reached through Hyperdrive, as the sole production authority.
5. `MarketCoordinator` Durable Objects for live coordination and event
   broadcast only.
6. A PostgreSQL transactional outbox for post-commit delivery.
7. A five-minute Cron Trigger for bounded, replay-safe simulation work.

The public compatibility API remains under `/api/*`. The current Worker
entrypoint remains `cloudflare/src/index.ts` while routes are extracted in
small, behavior-preserving slices. This is deliberate: the architecture is
modular in responsibility without requiring a risky all-at-once rewrite.

## Context

The master specification requires server-authoritative economic state,
deterministic simulation, strict transaction boundaries, runtime input
validation, append-only history, idempotent commands, and a verifiable
production readiness gate. The repository already contains domain adapters and
database migrations, but the Worker and Flutter entrypoints are still larger
than the desired feature boundaries.

The architecture must therefore optimize for four things at the same time:

- economic and operational correctness;
- small, reviewable vertical slices;
- fast and predictable AI-assisted changes;
- compatibility with the currently deployed API and database.

## Architectural boundaries

```text
Flutter Web client
  presentation, local view state, request transport
  never authoritative for credits, resources, ownership, rules, or outcomes
                     |
                     | JSON commands, queries, events
                     v
Cloudflare Worker
  request ID, CORS, authentication, validation, authorization,
  command/query routing, error normalization, response DTOs
                     |
                     v
TypeScript bounded contexts
  auth | market | governance | institutions | finance | lifecycle
  machines | technology | scheduler | read projections
  deterministic calculations + explicit repository operations
                     |
                     v
PostgreSQL through Hyperdrive
  transactions, locks, constraints, ledger, history, outbox, world clock
                     |
          +----------+----------+
          v                     v
MarketCoordinator DO      transactional outbox delivery
live sockets and broadcast  committed events and retries
coordination only           no canonical state
```

### Client boundary

The Flutter client may own presentation state, loading state, navigation,
cached read models, and local accessibility preferences. It must not calculate
or submit trusted balances, taxes, fills, production outcomes, governance
results, ownership transitions, or game-time advancement.

Financial and governance commands show an explicit pending state until the
server confirms success. Optimistic updates are limited to local visual state.

### Worker boundary

The Worker owns:

- session authentication and actor resolution;
- request parsing and runtime validation;
- authorization and institution scope checks;
- idempotency-key compatibility mapping;
- command/query dispatch;
- safe, stable response and error normalization;
- Cloudflare binding access;
- scheduling and outbox orchestration.

The Worker does not own canonical balances, ownership, game time, or mutable
request-independent authority state in module-level memory.

### Domain-module boundary

Domain modules own rules and persistence operations for one bounded context.
They may depend on the repository interface and pure calculation helpers. They
must not depend on HTTP `Request`, `Response`, Durable Object storage, or
Cloudflare-specific APIs.

The current source map is:

| Context | Current modules |
|---|---|
| Auth | `cloudflare/src/auth-postgres.ts` and auth helpers in `index.ts` |
| Market | `market-postgres.ts`, `money.ts` |
| Governance | `governance-postgres.ts`, `roles-postgres.ts`, `arbitration-postgres.ts` |
| Institutions | `institutions-postgres.ts`, `communities-postgres.ts` |
| Finance | `finance-postgres.ts`, `financial-postgres.ts`, `business-finance.ts` |
| Lifecycle | `lifecycle-postgres.ts` |
| Machines | `machines-postgres.ts`, `machines-recycling-postgres.ts` |
| Technology and AI | `technology-postgres.ts`, `ai-postgres.ts` |
| Scheduling | `scheduler-postgres.ts`, `scheduler-rules.ts`, `outbox-postgres.ts` |
| Read projections | `read-postgres.ts`, `world-postgres.ts`, `opportunities.ts` |

`production-catalog.ts` is the reference pattern for extracted read-only
product boundaries. New extraction should follow that pattern before a new
router or framework is introduced.

### Database boundary

PostgreSQL is the only production authority. All changes to money, resources,
ownership, legal status, governance outcomes, and world time must be committed
atomically in PostgreSQL. Database constraints, locks, migrations, and narrow
stored primitives protect invariants under contention.

`server.js` is a local reference simulator and compatibility harness only. It
is never a production fallback and cannot define production economic truth.

### Durable Object boundary

`MarketCoordinator` may serialize short-lived live coordination, accept WebSocket
connections, and broadcast committed events. It must not own balances,
ownership, settled prices, governance outcomes, inventory, or game time. A
restart must be recoverable from PostgreSQL and the outbox.

### Scheduler and outbox boundary

Cron work is bounded, deterministic, and replay-safe. It advances PostgreSQL
world state, records the scheduler heartbeat, and delivers only committed
outbox events. External delivery and WebSocket broadcast occur after the
authoritative transaction. Cloudflare Queues remain deferred until measured
backlog, retry-isolation, or throughput needs justify an ADR.

## Command and query rules

Every state-changing command follows this sequence:

1. Resolve the authenticated Human at the Worker boundary.
2. Validate the external input before domain execution.
3. Resolve `Idempotency-Key`; temporarily accept matching body
   `correlationId`; reject conflicting values.
4. Read the current game clock and active rule version.
5. Open one short PostgreSQL transaction.
6. Lock contested rows in deterministic order.
7. Re-check authorization and mutable facts inside the transaction.
8. Apply the domain operation and ledger/history changes.
9. Write the transactional outbox event in the same transaction.
10. Commit before external delivery.
11. Return a stable DTO with replay information when applicable.

Transactions must not contain email, WebSocket work, arbitrary network calls,
unbounded loops, or long-running calculations.

Every public error must be safe and machine-readable:

```json
{
  "ok": false,
  "error": "Safe human-readable message",
  "code": "STABLE_ERROR_CODE",
  "correlationId": "request-or-command-id"
}
```

Provider credentials, SQL text, stack traces, and raw database errors never
cross the public boundary.

## Modularity and AI-development rules

The repository deliberately uses a modular monolith rather than microservices.
AI-assisted changes must be made as one bounded vertical slice:

- one context or user journey at a time;
- one public contract change only when required;
- pure rules separated from database I/O;
- explicit input and output types at module boundaries;
- no hidden module-level state;
- tests beside the affected domain behavior;
- migrations forward-only and independently reviewable;
- production deployment only after the applicable readiness gate passes.

The Worker entrypoint may temporarily contain route glue, but new domain logic
must not be added there when a context module is an appropriate home.

## Alternatives considered

### Full microservices split

Rejected for the current phase. It would multiply deployment, data-consistency,
observability, and contract costs before EARTH has the measured scale that
requires independent services. It also makes AI changes span more repositories
and failure boundaries.

### Immediate Hono/Zod/Drizzle migration

Deferred. Hono, Zod, and Drizzle may be useful, but they do not solve the main
current risk: oversized route and client files plus incomplete vertical-slice
coverage. A migration is allowed only inside a bounded slice with measured
benefit, an ADR update, rollback steps, and unchanged PostgreSQL authority.

### Riverpod or generated Dart clients now

Deferred. Flutter uses hand-written transport and models while the DTO and error
contract stabilizes. Feature-first extraction is preferred first; state
management or client generation can be evaluated after repeated state-sharing
or contract-drift evidence exists.

### Durable Objects as authoritative state

Rejected. Durable Objects are useful for coordination and sockets, but putting
economic truth there would violate the PostgreSQL authority boundary and make
recovery and reconciliation harder.

## Consequences

### Benefits

- one authoritative economic state and one transaction boundary;
- small, deterministic domain modules that are easier to test and change;
- stable compatibility API during extraction;
- clear ownership of validation, rules, persistence, and delivery;
- lower cognitive load for human and AI contributors;
- incremental deployment and rollback by vertical slice.

### Costs and accepted trade-offs

- `index.ts` remains temporarily large as compatibility route glue;
- some transitional commands still accept legacy `correlationId` bodies;
- hand-written DTOs and client models require deliberate synchronization;
- a modular monolith requires discipline to prevent cross-context imports;
- deferred framework adoption means some validation and routing code is local.

These costs are accepted until evidence triggers a bounded migration.

## Migration plan

1. Keep `/api/*`, database identifiers, and response compatibility stable.
2. Extract route glue by bounded context, beginning with read-only or low-risk
   boundaries such as the production catalog and health/readiness handlers.
3. Extract command handlers with explicit actor, repository, request ID, and
   game-clock inputs.
4. Complete `Idempotency-Key` migration while retaining deliberate legacy
   compatibility and conflict rejection.
5. Expand domain integration tests for success, validation, authorization,
   replay, ledger/history, and outbox behavior.
6. Refactor Flutter from `main.dart` into feature-first modules while keeping
   the transport contract stable.
7. Reassess Hono, Zod, generated clients, Riverpod, Queues, or R2 only when a
   measured problem and a separate ADR justify the change.

## Rollback and failure handling

- Revert the bounded code commit if the API, transaction, or client gate fails.
- Do not roll back an applied production migration destructively; use a
  forward-compatible corrective migration.
- Recover live coordination from PostgreSQL and replayable outbox records.
- Treat a stale scheduler heartbeat, outbox retry failure, invariant failure,
  or schema mismatch as a failed readiness gate.
- Preserve append-only history and correct mistakes with compensating entries.

## Verification evidence

An implementation claiming conformance to this ADR must provide applicable
evidence for:

1. `npm test` and focused domain tests;
2. Cloudflare dry-run/config validation;
3. migration and schema-manifest verification;
4. Flutter analyze, tests, and release build when the client changes;
5. API contract tests for success, validation, authorization, replay, and safe
   errors;
6. integration evidence for balances plus ledger/history/outbox records when
   state changes;
7. production `/api/health` readiness with PostgreSQL authority;
8. one monitored scheduled game-day tick and outbox delivery;
9. manual verification of the changed user journey.

The current implementation and deployment status are tracked in:

- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)
- [`docs/API_CONTRACT.md`](API_CONTRACT.md)
- [`docs/FLUTTER_ARCHITECTURE.md`](FLUTTER_ARCHITECTURE.md)
- [`docs/POSTGRES_MIGRATION_STATUS.md`](POSTGRES_MIGRATION_STATUS.md)
- [`docs/ENGINEERING_PLAYBOOK.md`](ENGINEERING_PLAYBOOK.md)

## Review triggers

This ADR must be amended or superseded before:

- changing PostgreSQL as the production authority;
- introducing Hono, Zod, Drizzle, Riverpod, OpenAPI generation, Queues, or R2;
- changing the game-clock model or authority boundary;
- renaming immutable UC/OUC database identifiers;
- adding a monetized gameplay mechanic;
- splitting a bounded context into an independently deployed service.

Any amendment must state the problem, alternatives, migration and rollback
plans, operational cost, and verification evidence.
