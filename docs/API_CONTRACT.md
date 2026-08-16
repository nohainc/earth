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

EARTH natively supports the **Nano Markup** (`application/nanomarkup`) HTTP protocol:
- **Request Bodies**: Clients send requests with `Content-Type: application/nanomarkup` containing canonical Nano Markup text mappings (`..\n    key value`).
- **Response Bodies**: The Worker supports content negotiation; when requests include `Accept: application/nanomarkup` or `Content-Type: application/nanomarkup`, responses are returned with `Content-Type: application/nanomarkup; charset=utf-8` formatted as Nano Markup.
- **Internal State & Events**: Event details (`world_events.details`), negotiated contract terms (`terms_json`), governance rule values (`value_json`), and municipal tax charters (`charter_rules`) are canonically encoded using **Nano Markup** (`nanomarkup` by `nohainc`).

Clients utilize `NanoMarkupHelper` (Flutter) or the `nanomarkup` package (Node/TypeScript) with automatic fallback support for `application/json`.

## Authority and persistence

The Worker accepts data requests only when `PERSISTENCE_AUTHORITY=postgres` and
the `HYPERDRIVE` binding is configured. Production responses that mutate or
read gameplay state identify the persistence source as
`planetscale-postgres`.

The local `server.js` process is a reference simulator for compatibility tests;
it is not a production authority and must never be used as a deployment path.
