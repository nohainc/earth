# D1 cutover backup record

This record documents the latest remote D1 export used for the PostgreSQL
cutover gate.

- Source: Cloudflare remote database `earth-world`
- Export: `backups/earth-d1-cutover-backup.sql` (local durable workspace copy; excluded from Git)
- Export mode: data-only remote export
- Export size: 29,371 bytes
- Insert statements: 162
- SHA-256: `c8d3cc24939ff2bde2b5049cc6592a383238a53a09893746983d799ce4f66c3f`
- Captured: 2026-08-15

The export is intentionally excluded from Git because it contains user and
authentication data. The parity verifier is `npm run db:verify:d1-postgres`
with `D1_EXPORT=backups/earth-d1-cutover-backup.sql`; the rollback rehearsal is
`node scripts/test-backup-restore.mjs`. The final restore rehearsal still
requires an isolated PostgreSQL target or explicit approval for a temporary
transactional schema on the shared database.
