# EARTH Data Privacy, Classification & Retention Policy

## 1. Data Classification Matrix

| Classification | Scope & Description | Examples | Access Policy |
|---|---|---|---|
| **Public** | World signals, aggregate metrics, and public institutions | `world_events`, `market_prices`, `rankings_snapshots`, `deceased_profiles`, public proposal counts | Accessible unauthenticated |
| **Private** | Individual Human and corporate assets/financials | `account_balances`, `business_financials`, `notifications`, `succession_plans`, machine inventory | Strict owner/manager/shareholder authorization required |
| **Restricted / Secret** | Cryptographic secrets, authentication credentials, security tokens | `password_hash`, `password_salt`, `otp_secret`, `session_token`, `recovery_token`, Hyperdrive DB strings | NEVER exposed across API boundaries; never returned in responses, SSE streams, or error logs |

---

## 2. Public Projections & Redaction Rules

1. **Activity & History Queries**:
   - Aggregate world activity and history events project only `occurred_at`, `type`, `amount`, `game_day`, `actor` (public alias/id), `title`, `details`.
   - Any private bank account ID, internal credit debit routing, or authorization token is excluded.

2. **Live Event Broadcast (SSE & WebSocket)**:
   - Topic payloads broadcast only state change signals (e.g. `market.batch_settled`, `governance.vote_recorded`).
   - Private human credentials, OTP codes, and balance updates for other Humans are never broadcast to the global events channel.

3. **Error Envelope Sanitization**:
   - Errors return sanitized `code`, `error`, and `correlationId`.
   - SQL queries, stack traces, and database connection provider details are caught and replaced with generic safe messages (`SERVICE_UNAVAILABLE` or `VALIDATION_ERROR`).

---

## 3. Data Retention & Lifecycle Rules

- **Active Sessions**: Valid for up to 30 days; invalidated immediately on logout.
- **Login Rate Limits & OTP Codes**: 6-digit TOTP codes expire within 300s window; max 5 failed attempts per IP/Human before lockout.
- **Password Recovery Tokens**: Single-use tokens expire after 1 hour (3600s).
- **Notifications**: Retained for 90 game days; unread counts updated in real-time.
- **Event Outbox**: Completed events marked `processed_at` with deterministic idempotent keys; dead-letter items quarantined after 5 failed retries.
