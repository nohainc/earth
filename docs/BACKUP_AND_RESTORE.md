# EARTH PostgreSQL Database Backup, Restore & Disaster Recovery Runbook

## 1. Overview & Authority
PostgreSQL (PlanetScale/Hyperdrive) is the sole canonical persistence authority for all EARTH game state, economic ledgers, ownership records, identity accounts, governance ballots, and outbox queues.

---

## 2. Automated Backup Strategy

### Backup Cadence
- **Continuous Point-in-Time Recovery (PITR)**: Enabled on PlanetScale / PostgreSQL cluster (retained for 30 days).
- **Daily Automated Logical Backups**: Exported daily at 00:00 UTC using `pg_dump` with schema and data checksums.
- **Pre-Migration Snapshot**: Mandatory logical backup taken before running any forward migration in `db/migrations/`.

### Manual Backup Command
```bash
pg_dump --format=custom --no-owner --no-privileges \
  --dbname="${DATABASE_URL}" \
  --file="backups/earth-backup-$(date +%Y%m%d_%H%M%S).dump"
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
# 1. Create target database / schema
createdb -h localhost -U postgres earth_recovery

# 2. Restore custom dump
pg_restore --clean --if-exists --no-owner --no-privileges \
  --dbname="${RECOVERY_DATABASE_URL}" \
  "backups/earth-backup-<TIMESTAMP>.dump"

# 3. Verify schema manifest
DATABASE_URL="${RECOVERY_DATABASE_URL}" npm run db:verify:manifest

# 4. Verify post-restore economic invariants
DATABASE_URL="${RECOVERY_DATABASE_URL}" npm run db:verify:invariants
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
