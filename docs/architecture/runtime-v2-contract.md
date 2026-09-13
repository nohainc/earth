# EARTH Runtime V2 Contract

This document is the binding runtime architecture for EARTH. New work must
follow it. When existing code conflicts with this contract, reconcile the
code or remove the obsolete feature; do not restore a V1 table or authority
merely to satisfy an old caller.

## Authorities and boundaries

1. PostgreSQL is the authoritative store for game state: identity, Houses,
   Humans, institutions, economy, market, buildings, governance, research,
   lifecycle, and durable history.
2. Durable Objects provide transport and coordination infrastructure only.
   They may coordinate connections and broadcasts, but they must not own a
   second copy of canonical gameplay state.
3. Realtime events are delivery signals, not authoritative state. A client
   must be able to refresh its state from PostgreSQL-backed APIs.
4. Do not recreate V1 tables, functions, or compatibility models because
   runtime code still references them. Classify the feature as retained and
   rewrite it for V2, replace it with a V2 projection, or delete it.
5. Every public HTTP or realtime route has one canonical contract, one owner,
   one authentication class, and one domain service. The API registry is the
   source of that contract.
6. Backend responses must never invent plausible gameplay data. Missing
   catalog, rule, or world state is an error (or an explicit empty result when
   empty is the real state), not a fixture fallback.
7. Telemetry is operational data. It is not gameplay state and must not become
   an authority in the gameplay database.
8. Derived read models may be cached or materialized for performance, but they
   must be rebuildable from authoritative PostgreSQL state.
9. Flutter may call only endpoints present in the server API contract. Client
   fallbacks must not preserve removed routes.
10. EARTH is pre-production: removed endpoints are deleted, not retained as
    aliases, redirects, compatibility responses, or alternate handlers.

## Canonical route names

These names are reserved and must be used consistently:

| Method | Path | Meaning | Contract owner |
| --- | --- | --- | --- |
| GET | `/api/realtime` | Live transport/connection endpoint | System/Realtime routes |
| GET | `/api/house/daily-summary` | Current House daily read projection | House routes |
| POST | `/api/telemetry/error` | Operational client-error telemetry | System routes |
| GET | `/api/events` | Historical/read-model game events | Read-model routes |

`GET /api/events` and `GET /api/realtime` are deliberately different. The
events endpoint reads durable historical events. The realtime endpoint carries
live transport notifications and never defines game state.

## Removed routes and authorities

The following are removed from the active architecture and must not be
restored:

- `/edge/events`
- `/api/player/daily-briefing`
- legacy tables or APIs used only by those routes
- `app_error_logs` as a gameplay authority
- V1 tables reintroduced solely to satisfy stale runtime SQL

Operational telemetry may use a dedicated operational sink and the canonical
`/api/telemetry/error` endpoint. It must remain separate from gameplay state.

## Change discipline

Before implementing a feature, update the API registry and identify its
authoritative PostgreSQL state. Any derived projection must document its
rebuild source. Any removed route must be deleted from backend, Flutter,
tests, and documentation. Certification must verify route ownership,
authentication, PostgreSQL dependency availability, and the absence of
removed aliases.
