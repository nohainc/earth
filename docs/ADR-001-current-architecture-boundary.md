# ADR-001: Current architecture boundary

## Decision

EARTH remains a modular monolith with a Flutter client, direct TypeScript
Worker handlers, PostgreSQL through Hyperdrive, Durable Objects for live
coordination, and transactional outbox delivery.

PostgreSQL is the only production authority. `server.js` remains only as a
local reference simulator and compatibility harness. It is not a fallback for
the Worker and does not define production economic truth.

## Deferred recommendations

Hono, Zod, Riverpod, OpenAPI generation, and a multi-package domain layout are
deferred until a concrete maintenance or contract-generation need justifies
the migration. Existing runtime validation, explicit SQL adapters, the
versioned API contract, and focused vertical-slice tests are the current
equivalents.

## Migration trigger

Adopt one of the deferred tools only as part of a bounded vertical slice, with
measured benefit, no change to PostgreSQL authority, and a passing API,
transaction, Flutter, and deployment verification gate.
