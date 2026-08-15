# EARTH architecture and implementation rules

This document is the working architecture contract for future EARTH changes. It
exists to keep the game understandable as the specification grows and to make
each vertical slice safe to review, test, migrate, and deploy.

## 1. System boundaries

```text
Flutter web client
        |
        v
Cloudflare Worker
  HTTP/WebSocket boundary
  authentication and authorization
  runtime validation
  command orchestration
        |
        v
Domain rules in TypeScript
  deterministic calculations
  policy evaluation
  game-clock decisions
        |
        v
PostgreSQL repository
  explicit queries
  transaction boundaries
  idempotency coordination
        |
        v
PlanetScale PostgreSQL
  authoritative state
  constraints and indexes
  atomic financial primitives
  append-only history
```

PostgreSQL is the only persistence authority for EARTH. D1 is not a fallback,
shadow store, compatibility runtime, or second source of truth.

Cloudflare Durable Objects coordinate WebSocket fan-out and short-lived edge
coordination only. They do not own canonical game state. Queues and the
transactional outbox handle asynchronous delivery after the authoritative
database transaction commits.

## 2. Responsibility rules

### Worker and TypeScript

Keep these responsibilities in TypeScript:

- authentication, session handling, and authorization;
- request parsing and runtime validation;
- command orchestration and response DTOs;
- eligibility checks and policy selection;
- deterministic game rules and calculations;
- game-clock decisions;
- scheduler orchestration;
- event names, notification text, and external side effects;
- domain tests that should run without a database or Cloudflare runtime.

Domain code must not import Cloudflare APIs or depend on wall-clock time. Pass a
game clock or an explicit game-day value into deterministic rules.

### PostgreSQL

Use PostgreSQL for:

- primary and foreign-key integrity;
- `CHECK`, `UNIQUE`, and exclusion-style invariants where appropriate;
- non-negative balance and resource constraints;
- row locking for contested state;
- atomic debit/credit and resource transfers;
- ownership transitions;
- idempotency uniqueness and replay detection;
- append-only ledger, ownership, and historical event storage;
- transactional outbox records;
- reconciliation queries and authoritative projections.

Use numeric/decimal database values for money and authoritative quantities. Do
not introduce JavaScript floating-point arithmetic into a financial invariant.

## 3. Stored procedures and triggers

Stored functions are allowed only for narrow database mechanisms that need one
atomic operation under contention. Examples include:

- credit transfer;
- resource transfer;
- market reservation;
- market settlement;
- share or ownership transfer.

Market buy orders use an explicit PostgreSQL CREDIT escrow account. Reservation
funding, seller payment, market fee, price-difference refund, and cancellation
are separate idempotent transfers within the market transaction. The escrow
account is deleted after a fully settled or cancelled order; open legacy buy
orders are backfilled by a reviewed migration.

Such a function must have explicit parameters, deterministic lock ordering,
idempotency behavior, a small result shape, migration coverage, and a focused
integration test.

Do not move the following into stored procedures:

- complete gameplay systems;
- governance policy selection;
- production or AI rules;
- scheduler orchestration;
- notification text or external delivery;
- WebSocket fan-out;
- calls to external services.

Triggers are restricted to simple integrity protection, such as rejecting
mutation of append-only history. Avoid hidden business side effects. A normal
write should not unexpectedly create gameplay events, notifications, or money
movements through an invisible trigger.

## 4. Command transaction pattern

Every state-changing command should follow this order:

1. Authenticate the Human at the Worker boundary.
2. Authorize the requested action and institution scope.
3. Validate the request with a runtime schema.
4. Require a client or server-generated correlation/idempotency key.
5. Read the current game clock and applicable versioned rules.
6. Open one short PostgreSQL transaction.
7. Lock only the contested rows, in a deterministic order.
8. Re-check database facts that may have changed since authorization.
9. Apply the domain result through explicit SQL or a narrow SQL primitive.
10. Write the ledger/history and transactional outbox record together.
11. Commit before any external delivery or WebSocket broadcast.
12. Return a stable API DTO, never an unreviewed database row shape.

Transactions must not contain email delivery, network calls, WebSocket work,
long computations, or unbounded loops. Long-running simulation work must be
split into bounded, replayable batches.

## 5. Idempotency and history

- Every retry-sensitive command has a stable correlation ID.
- Replaying the same command returns the original result or an explicit
  `alreadyProcessed` result.
- Idempotency keys are enforced by a database uniqueness rule or serialized
  database primitive, not only by a prior `SELECT` in TypeScript.
- Ledger, ownership, membership, authority, and world-history records are
  append-only from application code.
- Corrections are compensating entries/events, never edits to historical facts.
- Outbox events are created in the same transaction as the state mutation and
  delivered asynchronously with retry and deduplication.

## 6. Rules and versioning

Gameplay coefficients must not be scattered as unexplained literals through
PostgreSQL units. Store policy values in versioned governance/world-rule
records, load the active version inside the command transaction, and record the
version on ledger or history entries.

If a rule changes the meaning of existing history, create a new rule version;
do not reinterpret old entries.

## 7. Repository and SQL rules

- Keep provider-specific SQL in `*-postgres.ts` adapters and the repository.
- Use explicit column lists for API-facing reads; avoid `SELECT *` in public
  response paths.
- Keep SQL parameterized. Never interpolate user-controlled values.
- Keep transactions short and use deterministic lock ordering.
- Add a bounded retry policy for classified transient serialization/deadlock
  errors at the repository boundary.
- Keep migrations immutable after production application. Create a new
  migration for every schema change.
- Do not use ORM push or ad-hoc production SQL outside the migration process.
- Update schema verification and migration documentation with each migration.

## 8. Vertical-slice workflow

Implement features end-to-end rather than building an isolated database layer
first. Each slice should contain:

1. domain rule and unit tests;
2. PostgreSQL migration/constraints if needed;
3. repository adapter and transaction behavior;
4. Worker route, authorization, and runtime validation;
5. Flutter client state/action/UI;
6. outbox/live-event behavior if applicable;
7. migration, smoke, and regression verification;
8. documentation and a focused production deployment only after review.

The slice is not complete when only the SQL or only the UI exists. The API,
database, client, tests, and operational verification must agree.

## 9. Testing requirements

At minimum, each state-changing slice needs:

- pure domain tests for normal, boundary, and invalid inputs;
- repository tests for commit and rollback behavior;
- concurrent/idempotent replay coverage where money or ownership is involved;
- migration application and schema-manifest verification;
- Worker smoke coverage for authorization and response errors;
- Flutter web analysis/tests for the affected client state and UI;
- production health and smoke verification after a major deployment.

Financial tests must verify both balances and ledger entries. Governance tests
must verify institution scope, eligibility, quorum, deadlines, and rule version.
Scheduler tests must verify replay safety and game-time, not wall-clock,
behavior.

## 10. Review checklist for future changes

Before merging a slice, confirm:

- Does the change preserve PostgreSQL as the only authority?
- Is the business policy in TypeScript and the data invariant in PostgreSQL?
- Are money and quantities decimal-safe?
- Is the transaction short, bounded, and correctly locked?
- Is replay behavior deterministic and idempotent?
- Are history and ledger records append-only?
- Are rules versioned and recorded?
- Are external effects after commit through the outbox?
- Are request schemas and response DTOs explicit?
- Are migration checksums, tests, smoke checks, and production status verified?
- Does the Flutter client consume the same contract exposed by the Worker?

When uncertain, prefer an explicit TypeScript orchestration step plus a narrow
database primitive over a large stored procedure or an implicit trigger.
