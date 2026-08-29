# AI implementation anti-patterns

1. **Floating-point money** — use `moneyToCents`/`centsToMoney`, never `Number` arithmetic for transfers.
2. **`SELECT *` in new queries** — select named columns so contracts remain intentional.
3. **Trusting client IDs** — authenticate and verify ownership or membership server-side.
4. **Missing idempotency** — mutation commands need a correlation/idempotency key and replay path.
5. **Direct balance mutation** — use `transferCredits` so ledger and balances agree.
6. **Writing to D1/SQLite** — PostgreSQL is the authoritative data store.
7. **Durable Object economic state** — persist economic facts in PostgreSQL transactions.
8. **Long cron work** — keep ticks bounded; split or queue expensive side effects.
9. **Hardcoded Flutter world state** — consume server snapshots and published rules.
10. **Skipping the outbox** — external effects must be recorded transactionally through `event_outbox`.

Before submitting a change, trace authorization, money precision, transaction boundaries, idempotency, and side-effect delivery.
