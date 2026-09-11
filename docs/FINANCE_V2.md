# Finance V2

> **Finance contracts may create claims, debts and obligations, but only the monetary authority may create CREDIT. Every other financial event moves existing CREDIT between Economy V2 accounts.**

Economy V2 is the authoritative financial model. `economic_accounts` hold live balances, `economic_transactions` and `economic_entries` provide the immutable audit trail, and the daily projection tables provide fast read models.

The Finance V2 acceptance audit is:

```sh
npm run db:verify:finance-acceptance
```

The audit is intentionally dependency-aware. It reports remaining shared gameplay callers before legacy accounting tables are removed. A green finance-owned audit does not authorize dropping legacy objects while scheduler, lifecycle, or institution callers still depend on them.

Key boundaries:

- Monetary issuance and retirement require explicit authority, reason, rule version, source, game day, and correlation ID.
- Deposits and loans are contracts backed by actual V2 transfers; accrual changes claims, not CREDIT balances.
- Taxes, dividends, bailouts, bankruptcy, and market escrow use V2 posting primitives.
- City fiscal stress uses receivership; corporate failure uses restructuring/liquidation; bank failure uses explicit resolution states.
- Daily projections and `earth_integrity_report()` detect conservation and contract violations.
