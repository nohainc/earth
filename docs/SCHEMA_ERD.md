# Core schema ERD

```mermaid
erDiagram
  humans ||--o{ accounts : owns
  accounts ||--o{ ledger_entries : records
  humans ||--o{ memberships : joins
  cities ||--o{ memberships : contains
  corporations ||--o{ memberships : contains
  humans ||--o{ businesses : owns
  businesses ||--o{ business_employees : employs
  businesses ||--|| business_financials : reports
  market_orders ||--o{ market_trades : fills
  governance_proposals ||--o{ ballots : receives
```

The immutable foundation is the clean baseline under `db/baseline/`, applied by
`db/migrations/001_baseline.sql` (schema version `1`). During pre-production
reconciliation, active forward migrations such as
`db/migrations/002_communities_v2.sql` are applied afterward. These temporary
migrations will be folded into the final baseline only after all retained
features pass fresh-database certification; future permanent changes then begin
at `002_...`.
