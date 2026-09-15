# EARTH V4 target architecture

This document is the compact architectural freeze for V4. It is subordinate
to the Constitution and the canonical domain model, and it exists so future
implementation work has one short, reviewable reference.

## Frozen vocabulary

- EARTH is the persistent shared world and global-rule authority.
- A House is the persistent player and economic-continuity boundary.
- A Human is a mortal representative of a House.
- A Territory is geography, capacity, services, and commons; it is not an
  economic owner or government.
- An Organization is a voluntary institution. Corporation and Community are
  transitional Organization archetypes, not mandatory hierarchy layers.
- Assets and physical Resources are distinct from CREDIT.
- Contracts and Proposals are explicit, auditable commitments and decisions.
- Voice is a governance allocation mechanism, not money or purchasing power.

## Authority boundaries

PostgreSQL is the sole authority for canonical state, game time, ownership,
balances, inventory, governance outcomes, and append-only history. TypeScript
validates requests, resolves authorization, applies deterministic rules, and
orchestrates bounded transactions. Flutter is an untrusted presentation
client. Durable Objects coordinate delivery and sockets only.

Every mutation authenticates and validates at the Worker boundary, uses a
stable idempotency/correlation key, re-checks contested facts inside one
PostgreSQL transaction, records the required ledger/history/outbox facts, and
commits before external delivery.

## Economy and settlement

Money and resource quantities use integer or PostgreSQL numeric semantics; no
floating-point calculation is authoritative. CREDIT movement uses balanced
ledger entries and explicit counterparties. Resource creation and consumption
use named production/consumption transactions rather than hidden wallets.

Daily settlement is a resumable sequence of bounded phase/shard work items.
Each phase is explicitly classified as required or deferred, supports lease,
retry, and replay semantics, and may not silently present a no-op as live
gameplay. Day close occurs only after the required barrier is complete.

## Product rule

The client presents a server-derived decision, quote, deadline, and resulting
state before a consequential action. Recommendations never mutate economic or
governance state. New gameplay must be implemented as a complete vertical
slice: schema, domain rule, API contract, client journey, settlement behavior
when applicable, replay/authorization tests, and operational evidence.

