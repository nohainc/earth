# EARTH release rehearsal

Run the maintained Phase 7 gate locally before a deployment:

```sh
DATABASE_URL='postgres://earth:earth_dev_only@localhost:5432/earth' npm run release:rehearse
```

The rehearsal is fail-closed and verifies migration ordering, the live schema manifest, canonical schema shape, PostgreSQL invariants, generated contracts, deployment route coverage, dependency security, mutation boundaries, Flutter analysis and release assets, backend certification, and local deployment canaries.

For an artifact-only check when PostgreSQL is intentionally unavailable:

```sh
npm run release:rehearse -- --skip-database
```

`--skip-database` must not be used as a production deployment substitute. Production deployment remains gated by the workflow's database backup, migration, manifest, invariant, readiness, and post-deploy checks.
