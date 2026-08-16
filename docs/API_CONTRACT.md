# EARTH API contract

EARTH uses a versioned REST/JSON contract. The current contract version is
`2026-08`, exposed through `X-EARTH-API-Version` on every response.

## Request identity

Clients may send `X-Request-ID`. The Worker preserves it as the request
correlation ID; otherwise it generates one. Retry-sensitive commands also
accept a command-specific `correlationId`, which is persisted by the
PostgreSQL transaction and controls replay behavior.

## Error envelope

Every JSON error returned by the Worker has this shape:

```json
{
  "ok": false,
  "error": "Authentication required",
  "code": "AUTHENTICATION_REQUIRED",
  "correlationId": "request-id"
}
```

`code` is stable for clients. `error` is safe display text. Provider errors,
SQL, credentials, and stack traces never cross the API boundary.

| HTTP status | Code |
| --- | --- |
| 400 | `VALIDATION_ERROR` |
| 401 | `AUTHENTICATION_REQUIRED` |
| 403 | `FORBIDDEN` |
| 404 | `NOT_FOUND` |
| 409 | `CONFLICT` |
| 429 | `RATE_LIMITED` |
| 503 | `SERVICE_UNAVAILABLE` |

## Serialization and Data Formats

While external HTTP requests accept standard REST payloads, internal serialized strings, event details (`world_events.details`), negotiated contract terms (`terms_json`), governance rule values (`value_json`), and municipal tax charters (`charter_rules`) are canonically encoded using **Nano Markup** (`nanomarkup` by `nohainc`).

Nano Markup provides high-density, human-readable structured serialization using 4-space indentation without type coercion ambiguity. Clients utilize `NanoMarkupHelper` or `nanomarkup` package decoders with automatic JSON backwards-compatibility fallback.

## Authority and persistence

The Worker accepts data requests only when `PERSISTENCE_AUTHORITY=postgres` and
the `HYPERDRIVE` binding is configured. Production responses that mutate or
read gameplay state identify the persistence source as
`planetscale-postgres`.

The local `server.js` process is a reference simulator for compatibility tests;
it is not a production authority and must never be used as a deployment path.
