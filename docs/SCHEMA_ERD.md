# EARTH Core Schema Map — V5

Status: **CURRENT HIGH-LEVEL REFERENCE**
Updated: 2026-09-19

This file is intentionally conceptual. The authoritative schema is
`db/schema.sql`, `db/schema-manifest.json`, and the active forward migration
chain.

```text
accounts / sessions
        |
        v
      houses  <----> humans
        |
        +---- house_affiliations ----> corporations
        |
        +---- buildings
        |
        +---- economic owner/accounts
                   |
                   +---- economic_transactions
                   +---- economic_entries
                   +---- resource/credit assets

corporations
   |
   +---- governance / proposals / roles
   +---- budgets / commitments / fiscal state
   +---- public buildings / technology / programs
   +---- pooled V5 physical-capacity state

territories
   |
   +---- standardized physical/geographic capacity context
   +---- audit/history/container records
   |
   X no independent government/treasury/player hierarchy in V5

communities
   |
   +---- voluntary social associations

EARTH
   |
   +---- Constitution / global governance
   +---- global programs / technology frontier
   +---- global capacity policy
```

## Rules

- City is not a current schema/domain authority.
- Territory is not an economic principal or a political layer.
- House and Corporation are the primary private/institutional economic owners.
- PostgreSQL is authoritative.
- Historical migrations may contain removed tables, columns, and vocabulary;
  they are append-only history and are not current schema documentation.
- Do not copy table lists or migration-head numbers into this document unless
  they are generated/verified from the current schema.
