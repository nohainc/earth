# Deployment database contract

The Worker and PostgreSQL database must agree on schema version `1`.

Deployment order is:

1. Verify the source commit and CI certification.
2. Back up the target database.
3. Run forward-only active migrations.
4. Verify the exact schema manifest and critical invariants.
5. Deploy the Worker and require readiness.

During pre-production reconciliation, use numbered forward migrations (`002_`,
`003_`, and later) and apply them incrementally. Do not edit an already-applied
migration or reset a database to investigate a runtime mismatch. After clean
local and remote certification, consolidate the temporary chain and freeze
`001_baseline.sql`; permanent future changes then start at `002_`. Migration
repair is not part of normal production deployment.
