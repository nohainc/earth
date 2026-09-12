# EARTH clean database baseline

This directory is the replacement starting point for a fresh EARTH database.
It is the only source for fresh installs. Migration `001_baseline.sql` is the
immutable first migration; future changes begin at `002_...`.

Run the baseline with PostgreSQL's `psql` client:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/baseline/001_baseline.sql
```

The bundle loads, in order:

1. `01_schema.sql` — final tables, constraints, and indexes
2. `02_functions.sql` — only final posting and integrity functions
3. `03_reference_data.sql` — canonical resources and reference rules
4. `04_initial_world.sql` — system owners, accounts, instruments, and clock

No normal players, test houses, demo buildings, orders, deposits, or research
projects are created here. Development and test fixtures belong under
`db/seed/` and are intentionally outside the production baseline.

`001_baseline.sql` is the freeze point. Future changes belong in new numbered
migrations after the baseline has been adopted; do not edit this bundle in
place.
