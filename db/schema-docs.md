# EARTH schema contract

The clean database baseline is migration version `1`.

The authoritative fresh-install bundle is `db/migrations/001_baseline.sql`,
assembled from four dependency-ordered sections:

1. `db/baseline/01_schema.sql` — tables, constraints, and indexes
2. `db/baseline/02_functions.sql` — runtime and integrity functions
3. `db/baseline/03_reference_data.sql` — canonical game configuration
4. `db/baseline/04_initial_world.sql` — required system state

`db/schema-manifest.json` is generated from the baseline schema and functions.
`cloudflare/src/schema-contract.ts` is generated from that manifest. These are
the inputs used by schema verification and readiness checks.

The migration runner applies only files marked `-- EARTH ACTIVE MIGRATION:`.
During the pre-production reconciliation phase, retained runtime gaps are
introduced as temporary forward migrations (`002_...`, `003_...`, and so on)
and applied incrementally with `npm run db:migrate:postgres`; do not reset the
local database between these changes. After local and remote certification,
the temporary chain is consolidated, `001_baseline.sql` is frozen, and the next
permanent change starts at `002_...`.

The baseline intentionally contains no demo players, fake Houses, test orders,
or legacy compatibility tables. Development and test fixtures belong under
`db/seed/` or `db/fixtures/`.
