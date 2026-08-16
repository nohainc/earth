# ADR-001: Current architecture boundary

## Decision

EARTH remains an incremental, bounded-context modular monolith with a Flutter
client, direct TypeScript Worker handlers, PostgreSQL through Hyperdrive,
Durable Objects for live coordination, and transactional outbox delivery.

The Worker keeps a thin compatibility entrypoint in `cloudflare/src/index.ts`,
while new work is organized as domain modules with explicit command handlers,
repository adapters, and stable response DTOs. Existing routes are extracted
gradually; the entrypoint is not replaced in one risky rewrite.

PostgreSQL is the only production authority. `server.js` remains only as a
local reference simulator and compatibility harness. It is not a fallback for
the Worker and does not define production economic truth.

## Deferred recommendations

Hono, Zod, Riverpod, OpenAPI generation, and a multi-package domain layout are
deferred until a concrete maintenance or contract-generation need justifies
the migration. Existing runtime validation, explicit SQL adapters, the
versioned API contract, and focused vertical-slice tests are the current
equivalents. A framework migration is not the selected path for making AI
development faster: small route/domain files, predictable command boundaries,
and mirrored tests provide the larger immediate benefit with less risk.

## Worker extraction rules

- Keep authentication, validation, authorization, and response normalization at
  the Worker boundary.
- Keep each state-changing command in one domain handler and one short
  PostgreSQL transaction.
- Pass an explicit command context containing actor, request ID, repository,
  and game clock; do not use module-level mutable authority state.
- Keep domain rules deterministic and independent of Cloudflare APIs.
- Add or update the domain test beside every extracted command.
- Extract by bounded context (`auth`, `market`, `governance`, `institutions`,
  `finance`, `lifecycle`, `machines`, `technology`, and `scheduler`) while
  preserving the public API contract.

## Migration trigger

Adopt one of the deferred tools only as part of a bounded vertical slice, with
measured benefit, no change to PostgreSQL authority, and a passing API,
transaction, Flutter, and deployment verification gate.
