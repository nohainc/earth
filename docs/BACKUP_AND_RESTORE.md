# EARTH PostgreSQL Database Backup, Restore & Disaster Recovery Runbook

## 1. Overview & Authority
PostgreSQL (PlanetScale/Hyperdrive) is the sole canonical persistence authority for all EARTH game state, economic ledgers, ownership records, identity accounts, governance ballots, and outbox queues.

---

## 2. Automated Backup Strategy

### Backup Cadence
- **Backup retention**: Keep daily logical backups for at least 30 days; retain monthly recovery points according to the launch data-retention policy.
- **Continuous Point-in-Time Recovery (PITR)**: Enable this in the managed PostgreSQL provider and retain at least 30 days.
- **Daily Automated Logical Backups**: Run `npm run db:backup:postgres` from the protected operations scheduler at 00:00 UTC. The command invokes `pg_dump` to write a custom-format dump and SHA-256 metadata; the destination must be encrypted at rest with restricted access.
- **Pre-Migration Snapshot**: Run the same command before every forward migration in `db/migrations/`.

### Manual Backup Command
```bash
DATABASE_URL="${DATABASE_URL}" EARTH_BACKUP_ENCRYPTED_AT_REST=true \
  npm run db:backup:postgres
```

---

## 3. Migration Preflight & Checksum Validation
Before applying any migration to production:
1. Verify migration file checksum integrity:
   ```bash
   node scripts/verify-schema-manifest.mjs
   ```
2. Verify database invariant preflight:
   ```bash
   node scripts/verify-postgres-invariants.mjs
   ```
3. Apply migration forward:
   ```bash
   node scripts/migrate-postgres.mjs
   ```

---

## 4. Restore & Recovery Procedure

### Isolated Restore Procedure
To restore a snapshot to a target database or staging instance:
```bash
# 1. Provision an empty isolated recovery database and restore the encrypted
#    backup file to a controlled operations host.
createdb -h localhost -U postgres earth_recovery

# 2. Restore custom dump with pg_restore (the script verifies its SHA-256 sidecar first)
RECOVERY_DATABASE_URL="${RECOVERY_DATABASE_URL}" \
EARTH_BACKUP_FILE="backups/earth-postgres-<TIMESTAMP>.dump" \
EARTH_ALLOW_RESTORE=true npm run db:restore:postgres

# 3. Verify schema manifest
DATABASE_URL="${RECOVERY_DATABASE_URL}" npm run db:verify:manifest

# 4. Verify post-restore economic invariants
DATABASE_URL="${RECOVERY_DATABASE_URL}" npm run db:verify:invariants

# 5. Reconcile the restored database and resume the scheduler only after all
#    checks pass. Restore Hyperdrive/deployment secrets from the secret manager;
#    never place them in the dump, repository or runbook.
```

---

## 5. Rollback & Forward-Fix Procedures

### Forward-Fix Rule (Preferred)
In append-only financial and governance ledgers, forward migrations (`0018_fix_...sql`) are preferred over destructive down-migrations to ensure complete audit trail preservation.

### Database Failover / Rollback Steps
1. Switch Hyperdrive connection string secret to the restored snapshot or standby replica.
2. In Cloudflare Worker, verify readiness probe:
   ```bash
   curl -i https://earth.nohainc.com/api/ready
   ```
3. Run post-failover smoke test:
   ```bash
   npm run cf:smoke
   ```
