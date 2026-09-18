# EARTH clean database baseline

This directory contains the frozen source sections for migration
`db/migrations/001_baseline.sql`. It is not a complete current-schema install:
later tables and functions are introduced by active forward migrations.
Migration `001_baseline.sql` is the immutable first migration; future changes
continue through the numbered active chain.

Fresh databases must be installed through the migration runner:

```bash
DATABASE_URL="$DATABASE_URL" npm run db:migrate:postgres
```

The bundle loads, in order:

1. `01_schema.sql` — baseline tables, constraints, and indexes
2. `02_functions.sql` — baseline posting and integrity functions
3. `03_reference_data.sql` — canonical resources and reference rules
4. `04_initial_world.sql` — system owners, accounts, instruments, and clock

No normal players, test houses, demo buildings, orders, deposits, or research
projects are created here. Development and test fixtures belong under
`db/seed/` and are intentionally outside the production baseline.

Domain changes belong in new numbered forward migrations under
`db/migrations/` and are applied incrementally. Do not reset the local database
between those changes. The migration chain is the canonical installation path;
the source sections are not used directly by application environments.
