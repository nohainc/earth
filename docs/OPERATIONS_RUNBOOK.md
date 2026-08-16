# EARTH Production Operations & Recovery Runbook

## 1. Production Health & Readiness Probes

### Endpoints
- **Health Check**: `GET /api/health` or `GET /health`
  - Returns `200 OK` with detailed JSON status when all core subsystems are operational.
  - Returns `503 Service Unavailable` if PostgreSQL connectivity or core invariants fail.
- **Readiness Check**: `GET /api/ready` or `GET /ready`
  - Returns `200 OK` when the system is ready to accept traffic and the scheduler heartbeat is within tolerance ($\le 900$s).

### Monitored Metrics
- **PostgreSQL Connectivity & Latency**: `checks.postgresReachable`, `checks.postgresSchemaReady`, `checks.postgresDataReady`
- **Schema Manifest & Migration Version**: `checks.migrationManifest`, `readiness.migrationVersion`
- **Scheduler Freshness**: `checks.schedulerFresh`, `readiness.schedulerAgeSeconds` ($\le 900$s)
- **Outbox Delivery Backlog**: `checks.outboxPressure` (pending $< 1000$), `checks.outboxRetryFailures` ($= 0$)
- **Invariant Scans**: `checks.balancesNonNegative` ($= \text{true}$), `checks.machineConditionsBounded` ($= \text{true}$)

---

## 2. Incident Recovery Procedures

### A. Database Connection Failure (`SERVICE_UNAVAILABLE`)
**Symptoms**: `/api/health` reports `checks.database = false` or `checks.postgresReachable = false`. Client receives HTTP 503 with code `SERVICE_UNAVAILABLE`.
**Diagnosis**:
1. Check Cloudflare Hyperdrive binding status in Cloudflare Dashboard -> Storage & Databases -> Hyperdrive.
2. Verify PostgreSQL cluster health on PlanetScale / Postgres host.
3. Verify connection pool saturation:
   ```bash
   npm run cf:assert-postgres
   ```
**Resolution**:
1. If Hyperdrive pool is hung, rotate or refresh the Hyperdrive configuration ID in `wrangler.api.jsonc`.
2. If direct database failover occurred, update the database connection string secret in Hyperdrive.
3. Validate restoration:
   ```bash
   DATABASE_URL="postgres://..." npm run test:postgres
   ```

---

### B. Scheduler Failure / Stale Heartbeat
**Symptoms**: `/api/health` reports `checks.schedulerFresh = false` with `schedulerAgeSeconds > 900`.
**Diagnosis**:
1. Check Cloudflare Cron Triggers execution logs in Cloudflare Dashboard -> Workers & Pages -> `earth-world` -> Logs.
2. Confirm if the cron trigger fired every minute (`* * * * *`).
**Resolution**:
1. Trigger an authoritative clock advance command via authorized OUC Delegate or administrator script:
   ```bash
   node scripts/run-simulation-scenarios.mjs
   ```
2. Verify scheduler timestamp in PostgreSQL:
   ```sql
   SELECT last_scheduler_at, game_day, game_minute FROM world_state WHERE id = 'WORLD';
   ```

---

### C. Outbox Backlog & Retry Pressure
**Symptoms**: `outboxPending >= 1000` or `outboxRetryFailures > 0` or dead-letter count $> 0$.
**Diagnosis**:
1. Query the outbox table for failed events:
   ```sql
   SELECT id, topic, event_key, attempts, last_error, created_at
   FROM event_outbox
   WHERE processed_at IS NULL AND attempts > 0
   ORDER BY created_at DESC LIMIT 20;
   ```
2. Check Durable Object `MarketCoordinator` connectivity.
**Resolution**:
1. Flush and redeliver pending events:
   ```sql
   UPDATE event_outbox
   SET attempts = 0, locked_at = NULL, last_error = NULL
   WHERE processed_at IS NULL AND last_error LIKE 'RETRYABLE%';
   ```
2. For unrecoverable dead-letter events, inspect the payload, record audit logs, and mark processed.

---

### D. Worker Deployment Rollback Procedure
**Symptoms**: Regression in API behavior, unexpected exceptions, or asset loading failure following a deployment.
**Procedure**:
1. List recent deployments:
   ```bash
   npx wrangler deployments list
   ```
2. Rollback to the previous stable deployment ID:
   ```bash
   npx wrangler rollback <DEPLOYMENT_ID>
   ```
3. Verify database schema compatibility with the rolled-back Worker version (`db:verify:manifest`).
4. Execute smoke suite against production target:
   ```bash
   npm run cf:smoke
   ```
