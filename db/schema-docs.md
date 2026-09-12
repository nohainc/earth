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

Historical SQL files remain archived source material. The migration runner
applies only files marked `-- EARTH ACTIVE MIGRATION:`. Migration `001` is
immutable after the clean databases are accepted; future changes use `002_...`
and later active migrations.

The baseline intentionally contains no demo players, fake Houses, test orders,
or legacy compatibility tables. Development and test fixtures belong under
`db/seed/` or `db/fixtures/`.
