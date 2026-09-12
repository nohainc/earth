# Deployment database contract

The Worker and PostgreSQL database must agree on schema version `1`.

Deployment order is:

1. Verify the source commit and CI certification.
2. Back up the target database.
3. Run forward-only active migrations.
4. Verify the exact schema manifest and critical invariants.
5. Deploy the Worker and require readiness.

`001_baseline.sql` is immutable after clean environments are accepted. Future
schema changes are numbered `002_...` and later. Migration repair is not part
of normal production deployment.
