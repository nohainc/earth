# EARTH schema contract

The clean database baseline is migration version `1`.

The authoritative fresh-install path is the active migration chain:
`db/migrations/001_baseline.sql` followed by every active migration through the
current migration head. Migration 001 is assembled from four frozen,
dependency-ordered source sections:

1. `db/baseline/01_schema.sql` — tables, constraints, and indexes
2. `db/baseline/02_functions.sql` — runtime and integrity functions
3. `db/baseline/03_reference_data.sql` — canonical game configuration
4. `db/baseline/04_initial_world.sql` — required system state

The source sections are intentionally not a complete current schema: objects
introduced by later migrations, such as settlement and market processing
controls, belong to the forward chain. `db/schema-manifest.json` describes the
result after that chain has been applied.
`cloudflare/src/schema-contract.ts` is generated from that manifest. These are
the inputs used by schema verification and readiness checks.

The migration runner applies only files marked `-- EARTH ACTIVE MIGRATION:` and
is the only supported fresh-install mechanism.
During the pre-production reconciliation phase, retained runtime gaps are
introduced as temporary forward migrations (`002_...`, `003_...`, and so on)
and applied incrementally with `npm run db:migrate:postgres`; do not reset the
local database between these changes. After local and remote certification,
the temporary chain is consolidated, `001_baseline.sql` is frozen, and the next
permanent change starts at `002_...`.

The baseline intentionally contains no demo players, fake Houses, test orders,
or legacy compatibility tables. Development and test fixtures belong under
`db/seed/` or `db/fixtures/`.
