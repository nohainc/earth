# EARTH V4 domain model

This is the repository-facing vocabulary for the V4 gameplay transition. It
supersedes older documents that use City as an institutional authority or
Corporation as the mandatory parent of a House.

| Concept | Meaning | Authority |
| --- | --- | --- |
| EARTH | The persistent shared world and its global rules | PostgreSQL |
| House | Persistent player identity, owner, and continuity boundary | PostgreSQL |
| Human | Mortal representative acting for a House | PostgreSQL |
| Territory | Geography, capacity, services, and commons | PostgreSQL |
| Organization | Voluntary institution that can operate, own, govern, or provide services | PostgreSQL |
| Asset | Durable productive or territorial right | PostgreSQL |
| CREDIT | Atomic monetary asset moved through the balanced ledger | PostgreSQL |
| Resource | Physical stock or flow settled from an opening snapshot | PostgreSQL |
| Contract / Proposal | Explicit obligation or decision with deadlines and history | PostgreSQL |

Corporation and Community are transitional Organization archetypes. They are
not ownership, residency, or geography authorities. A House may participate in
multiple Organizations and may reside in a Territory independently.

## Decision-first gameplay

The Command Center is a read-model surface. Its queue is derived from server
facts such as resource pressure, Territory capacity, obligations, proposals,
research, market demand, and House continuity. It does not mutate balances,
prices, production, or governance state. Actions continue through the relevant
authoritative endpoint and must use server-side validation and idempotency.

## Implementation boundary

Flutter is an untrusted presentation client. TypeScript validates and
orchestrates requests. PostgreSQL owns canonical state, locking, constraints,
balanced economic entries, idempotency, and append-only history. Durable
Objects coordinate live delivery only.
