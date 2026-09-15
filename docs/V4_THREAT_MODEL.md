# EARTH V4 Economic Threat Model

This is the minimum review checklist for every new economic or governance
mechanic. PostgreSQL constraints, locks, and the canonical ledger are the
security boundary; UI validation and request rate limits are supplementary.

| Threat | Required control | Current V4 control |
| --- | --- | --- |
| Replay / duplicate command | Stable correlation key plus unique constraint | `economic_transactions`, entitlement, membership, grant, proposal and policy correlation keys |
| Race / double spend | Lock contested row inside the transaction | Ledger posting, bank loans, budgets, ownership, resolution and entry-support locks |
| Stale quote | Re-read price, balance, authorization and expiry in command transaction | Finance, construction, market, governance and banking commands |
| Self-dealing / wash trade | Counterparty and ownership checks | Market owner validation and canonical order escrow |
| Sybil / grant farming | One-time, bounded eligibility tied to House progress | `house_entry_support` requires new entry window, no buildings/orders/affiliation, and is one-per-House |
| Privilege escalation | Current Charter/office/membership check in transaction | Organization authority and governance services |
| Circular funding | Explicit source/destination and budget authority | Global programs, public matching, organization budgets and bank reserve controls |
| Unbalanced issuance | Canonical ledger posting and asset-specific invariants | `earth_post_transaction` / `earth_issue_starter_package` only |
| Historical reinterpretation | Effective-dated immutable records | Jurisdiction, technology, rankings and world conditions |
| Commons diversion / dividend overpayment | Revenue snapshot, governed allocation, beneficiary cash check, proportional integer payout and explicit remainder | Territory lease payments, commons declarations and dividend settlement |

Every new state-changing endpoint must document its applicable rows before
implementation and add replay plus concurrency coverage. A positive rate-limit
result never substitutes for any row-level invariant above.
