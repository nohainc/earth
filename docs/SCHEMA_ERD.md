# Core schema ERD (V3)

```mermaid
erDiagram
  houses ||--o{ humans : represents
  houses ||--o{ house_affiliations : joins
  corporations ||--o{ house_affiliations : admits
  corporations ||--o{ territories : governs
  territories ||--o{ buildings : locates
  owner_registry ||--o{ buildings : owns
  market_orders ||--o{ market_fills : fills
  proposals ||--o{ ballots : receives
```

The clean-break foundation is the V3 baseline under `db/baseline/`, applied by
`db/migrations/001_baseline.sql` (schema head `3`). During pre-production
reconciliation, active forward migrations such as
`db/migrations/002_communities_v2.sql` and
`db/migrations/003_community_v2_hardening.sql` are applied afterward. These temporary
migrations will be folded into the final baseline only after all retained
features pass fresh-database certification; future permanent changes then begin
at `002_...`.
