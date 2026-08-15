# Historical cutover record

This record documents the historical remote export used during the PostgreSQL
cutover. It is retained as an audit note only; it is not an active runtime
dependency or recovery procedure.

- Source: Cloudflare remote database `earth-world`
- Export: `backups/earth-d1-cutover-backup.sql` (local durable workspace copy; excluded from Git)
- Export mode: data-only remote export
- Export size: 29,371 bytes
- Insert statements: 162
- SHA-256: `c8d3cc24939ff2bde2b5049cc6592a383238a53a09893746983d799ce4f66c3f`
- Captured: 2026-08-15

The export is intentionally excluded from Git because it contains user and
authentication data. The Earth D1 database has since been removed and the
application is PostgreSQL-only. Current recovery uses PlanetScale/PostgreSQL
backups and the versioned schema in `db/migrations/`; the historical export is
not used by deployment or application code.
