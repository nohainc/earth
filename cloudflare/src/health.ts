import { probePostgres } from './postgres';
import { withPostgresRepository } from './repository';
import { EARTH_SCHEMA_VERSION } from './schema-contract.ts';

export async function livenessResponse(request: Request): Promise<Response> {
  return Response.json({
    ok: true,
    status: 'live',
    correlationId: request.headers.get('X-Request-ID') ?? crypto.randomUUID(),
  });
}

export async function healthResponse(request: Request, env: Env, options: { readiness?: boolean } = {}): Promise<Response> {
  const postgres = await probePostgres(env.HYPERDRIVE);
  const baseHealth = {
    correlationId: request.headers.get('X-Request-ID') ?? crypto.randomUUID(),
    persistence: 'planetscale-postgres',
    authority: 'postgres',
    environment: env.ENVIRONMENT,
    workerVersion: '0.1.0',
    schemaVersion: postgres.migrationVersion ?? null,
    expectedSchemaVersion: EARTH_SCHEMA_VERSION,
  };

  // Do not run the detailed health queries against an incompatible schema.
  // This keeps readiness diagnostic and fail-closed when a migration is
  // missing, while avoiding a second error from querying absent objects.
  if (!postgres.configured || !postgres.reachable || !postgres.schemaReady) {
    const checks = {
      database: postgres.reachable,
      postgresConfigured: postgres.configured,
      postgresReachable: postgres.reachable,
      postgresSchemaReady: postgres.schemaReady,
      postgresDataReady: false,
      coreSchema: false,
      featureSchema: false,
      criticalInvariants: false,
      migrationManifest: postgres.migrationVersion === EARTH_SCHEMA_VERSION,
    };
    return Response.json({
      ...baseHealth,
      ok: false,
      checks,
      postgres: {
        serverVersion: postgres.serverVersion ?? null,
        featureTableCount: postgres.featureTableCount ?? 0,
        dataReady: false,
        missingObjects: postgres.missingObjects ?? [],
      },
      readiness: {
        migrationVersion: postgres.migrationVersion ?? null,
        expectedSchemaVersion: EARTH_SCHEMA_VERSION,
        schemaMissingObjects: postgres.missingObjects ?? [],
      },
      migration: { target: 'planetscale-postgres', stage: 'not-ready' },
    }, { status: 503 });
  }
  const postgresChecks = await withPostgresRepository(env, async (repository) => {
    const [core, feature, reservations, governance, financial, assets, taxed, invariants, scheduler, outbox, migrations, counts, settlement, observability] = await Promise.all([
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state', 'humans', 'market_prices', 'account_balances', 'ledger_entries', 'ownership_events', 'membership_events']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['buildings', 'civic_dividend_payouts', 'global_bank_deposits']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_quote_units'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['corporations', 'cities']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'personal_financial_states'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'buildings'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'buildings' AND column_name = 'daily_operating_credits'"),
      repository.query<{ invalid: string }>(`SELECT COALESCE(SUM(invalid_count) FILTER (WHERE invalid_count > 0), 0)::text AS invalid FROM earth_integrity_report()`),
      repository.query("SELECT EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_scheduler_at)) AS age_seconds FROM world_state WHERE id = 'WORLD'"),
      repository.query(`
        SELECT
          COUNT(*) FILTER (WHERE processed_at IS NULL)::integer AS pending,
          COUNT(*) FILTER (WHERE processed_at IS NULL AND attempts > 0)::integer AS retrying,
          COUNT(*) FILTER (WHERE processed_at IS NULL AND locked_at IS NOT NULL AND locked_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes')::integer AS stale_locks,
          COUNT(*) FILTER (WHERE last_error LIKE 'DEAD_LETTER%')::integer AS dead_lettered,
          COUNT(*) FILTER (WHERE attempts >= 5)::integer AS failed,
          EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(created_at) FILTER (WHERE processed_at IS NULL)))::numeric AS oldest_pending_age,
          MAX(processed_at)::text AS last_delivery
        FROM event_outbox
      `),
      repository.query('SELECT COALESCE(MAX(version), 0)::integer AS version FROM earth_schema_migrations'),
      Promise.all([
        repository.query('SELECT COUNT(*)::integer AS count FROM humans'),
        repository.query('SELECT COUNT(*)::integer AS count FROM buildings WHERE ownership_class = \'private\''),
        repository.query('SELECT COUNT(*)::integer AS count FROM ledger_entries'),
        repository.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'"),
      ]),
      repository.query<{
        status: string;
        current_game_day: string;
        last_completed_game_day: string | null;
        backlog_game_days: string;
        last_completed_at: string | null;
        current_phase: string | null;
        lease_owner: string | null;
        lease_heartbeat_at: string | null;
        phase_completed: string;
        phase_total: string;
        failed_runs: string;
        retry_count: string;
      }>(`
        WITH clock AS (
          SELECT earth_game_day_from_total_minutes(total_game_minutes) AS current_game_day
          FROM earth_get_current_game_time()
        ), watermark AS (
          SELECT earth_settlement_watermark(clock.current_game_day) AS game_day
          FROM clock
        ), completed AS (
          SELECT r.game_day, r.completed_at
          FROM daily_settlement_runs r
          JOIN watermark w ON w.game_day = r.game_day
          WHERE r.status IN ('completed', 'baseline')
        )
        SELECT control.status,
               clock.current_game_day::text,
               completed.game_day::text AS last_completed_game_day,
               GREATEST(0, (clock.current_game_day - 1) - COALESCE(completed.game_day, 0))::text AS backlog_game_days,
               completed.completed_at::text AS last_completed_at,
               active.current_phase,
               active.lease_owner,
               active.lease_heartbeat_at::text,
               COALESCE((SELECT COUNT(*) FROM daily_settlement_phase_runs p WHERE p.game_day = active.game_day AND p.status = 'completed'), 0)::text AS phase_completed,
               COALESCE((SELECT COUNT(*) FROM daily_settlement_phase_runs p WHERE p.game_day = active.game_day), 0)::text AS phase_total,
               (SELECT COUNT(*) FROM daily_settlement_runs r WHERE r.status = 'failed')::text AS failed_runs,
               (SELECT COALESCE(SUM(attempt_count), 0) FROM daily_settlement_runs)::text AS retry_count
        FROM daily_settlement_control control CROSS JOIN clock
        LEFT JOIN completed ON TRUE
        LEFT JOIN LATERAL (SELECT r.game_day, r.current_phase, r.lease_owner, r.lease_heartbeat_at
                             FROM daily_settlement_runs r
                            WHERE r.status = 'running'
                            ORDER BY r.game_day DESC LIMIT 1) active ON TRUE
        WHERE control.id = 'WORLD'
      `),
      Promise.all([
        repository.query<{ active: string }>("SELECT COUNT(*)::text AS active FROM pg_stat_activity WHERE datname = current_database() AND state <> 'idle'").catch(() => ({ rows: [{ active: '0' }] })),
        repository.query<{ api_errors: string; worker_errors: string }>(`SELECT
          COUNT(*) FILTER (WHERE source IN ('api', 'http'))::text AS api_errors,
          COUNT(*) FILTER (WHERE source IN ('worker', 'scheduler'))::text AS worker_errors
          FROM app_error_logs WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'`).catch(() => ({ rows: [{ api_errors: '0', worker_errors: '0' }] })),
        repository.query<{ slow_queries: string }>(`SELECT COUNT(*)::text AS slow_queries FROM pg_stat_statements WHERE mean_exec_time >= 1000`).catch(() => ({ rows: [{ slow_queries: '0' }] })),
        repository.query<{ active_buildings: string; inactive_buildings: string }>(`SELECT
          COUNT(*) FILTER (WHERE status = 'active')::text AS active_buildings,
          COUNT(*) FILTER (WHERE status <> 'active')::text AS inactive_buildings FROM buildings`).catch(() => ({ rows: [{ active_buildings: '0', inactive_buildings: '0' }] })),
        repository.query<{ market_orders_processed: string }>(`SELECT COUNT(*)::text AS market_orders_processed
          FROM market_orders WHERE updated_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'`).catch(() => ({ rows: [{ market_orders_processed: '0' }] })),
      ]),
    ]);
    const schedulerAgeSeconds = Number(scheduler.rows[0]?.age_seconds ?? Number.POSITIVE_INFINITY);
    const schedulerState = schedulerAgeSeconds <= 180 ? 'healthy' : schedulerAgeSeconds <= 600 ? 'degraded' : 'critical';
    const outboxRow = outbox.rows[0];
    const outboxPending = Number(outboxRow?.pending ?? 0);
    const outboxRetrying = Number(outboxRow?.retrying ?? 0);
    const outboxStaleLocks = Number(outboxRow?.stale_locks ?? 0);
    const outboxDeadLettered = Number(outboxRow?.dead_lettered ?? 0);
    const outboxRetryFailures = Number(outboxRow?.failed ?? 0);
    const outboxOldestAgeSeconds = outboxRow?.oldest_pending_age != null ? Number(outboxRow.oldest_pending_age) : null;
    const outboxLastDeliveryAt = outboxRow?.last_delivery ?? null;
    const settlementRow = settlement.rows[0];
    const [connectionRow, errorRow, slowQueryRow, buildingRow, marketRow] = observability;
    const settlementBacklog = Number(settlementRow?.backlog_game_days ?? Number.POSITIVE_INFINITY);
    const settlementStatus = settlementRow?.status ?? 'unavailable';
    return {
      checks: {
        database: true,
        coreSchema: postgres.schemaReady,
        featureSchema: postgres.schemaReady,
        marketCreditReservations: Number(reservations.rows[0]?.count ?? 0) === 1,
        businessGovernanceSchema: Number(governance.rows[0]?.count ?? 0) === 2,
        businessFinancialSchema: Number(financial.rows[0]?.count ?? 0) === 1,
        buildingAssetSchema: Number(assets.rows[0]?.count ?? 0) === 1,
        businessTaxSchema: Number(taxed.rows[0]?.count ?? 0) === 1,
        balancesNonNegative: Number(invariants.rows[0]?.invalid ?? 0) === 0,
        criticalInvariants: Number(invariants.rows[0]?.invalid ?? 0) === 0,
        schedulerFresh: schedulerState !== 'critical',
        outboxPressure: outboxPending < 1000,
        outboxRetryFailures: outboxRetryFailures === 0,
        dailySettlementBacklog: settlementStatus !== 'active' || settlementBacklog <= 1,
        migrationManifest: Number(migrations.rows[0]?.version ?? 0) === EARTH_SCHEMA_VERSION,
      },
      readiness: {
        schedulerAgeSeconds: Number.isFinite(schedulerAgeSeconds) ? schedulerAgeSeconds : null,
        schedulerState,
        outboxPending,
        outboxRetryFailures,
        outboxMetrics: {
          pendingCount: outboxPending,
          retryCount: outboxRetrying,
          staleLocksCount: outboxStaleLocks,
          deadLetterCount: outboxDeadLettered,
          oldestPendingAgeSeconds: outboxOldestAgeSeconds,
          lastSuccessfulDeliveryAt: outboxLastDeliveryAt,
        },
        migrationVersion: Number(migrations.rows[0]?.version ?? 0),
        expectedSchemaVersion: EARTH_SCHEMA_VERSION,
        schemaMissingObjects: postgres.missingObjects ?? [],
        dailySettlement: {
          status: settlementStatus,
          currentGameDay: settlementRow?.current_game_day != null ? Number(settlementRow.current_game_day) : null,
          lastCompletedGameDay: settlementRow?.last_completed_game_day != null ? Number(settlementRow.last_completed_game_day) : null,
          backlogGameDays: Number.isFinite(settlementBacklog) ? settlementBacklog : null,
          lastCompletedAt: settlementRow?.last_completed_at ?? null,
          currentPhase: settlementRow?.current_phase ?? null,
          leaseOwner: settlementRow?.lease_owner ?? null,
          leaseHeartbeatAt: settlementRow?.lease_heartbeat_at ?? null,
          phaseProgress: {
            completed: Number(settlementRow?.phase_completed ?? 0),
            total: Number(settlementRow?.phase_total ?? 0),
          },
          failedRuns: Number(settlementRow?.failed_runs ?? 0),
          retryCount: Number(settlementRow?.retry_count ?? 0),
        },
        worldHealth: {
          humanCount: Number(counts[0].rows[0]?.count ?? 0),
          cityCount: Number((await repository.query('SELECT COUNT(*)::integer AS count FROM cities')).rows[0]?.count ?? 0),
          corporationCount: Number((await repository.query('SELECT COUNT(*)::integer AS count FROM corporations')).rows[0]?.count ?? 0),
          activeBuildings: Number(buildingRow.rows[0]?.active_buildings ?? 0),
          inactiveBuildings: Number(buildingRow.rows[0]?.inactive_buildings ?? 0),
          marketOrdersProcessed24h: Number(marketRow.rows[0]?.market_orders_processed ?? 0),
          dbConnections: Number(connectionRow.rows[0]?.active ?? 0),
          slowQueries24h: Number(slowQueryRow.rows[0]?.slow_queries ?? 0),
          apiErrors24h: Number(errorRow.rows[0]?.api_errors ?? 0),
          workerErrors24h: Number(errorRow.rows[0]?.worker_errors ?? 0),
          failedSettlementRuns: Number(settlementRow?.failed_runs ?? 0),
        },
        invariantScan: {
          ok: Number(invariants.rows[0]?.invalid ?? 0) === 0,
          balancesNonNegative: Number(invariants.rows[0]?.invalid ?? 0) === 0,
        },
      },
      counts: {
        humans: Number(counts[0].rows[0]?.count ?? 0),
        privateBuildings: Number(counts[1].rows[0]?.count ?? 0),
        ledger: Number(counts[2].rows[0]?.count ?? 0),
        world: Number(counts[3].rows[0]?.count ?? 0),
      },
    };
  }).catch(() => undefined);
  const checks = postgresChecks?.checks ?? {
    database: false, coreSchema: false, featureSchema: false,
    marketCreditReservations: false, businessGovernanceSchema: false, businessFinancialSchema: false,
    buildingAssetSchema: false, businessTaxSchema: false, balancesNonNegative: false, criticalInvariants: false,
  };
  const shadow = postgresChecks?.counts ?? null;
  const readinessChecks = {
    ...checks,
    postgresConfigured: postgres.configured,
    postgresReachable: postgres.reachable,
    postgresSchemaReady: postgres.schemaReady,
    postgresDataReady: postgres.dataReady,
  };
  const ok = Object.values(readinessChecks).every(Boolean);
  return Response.json({
    correlationId: request.headers.get('X-Request-ID') ?? crypto.randomUUID(),
    ok,
    checks: { ...readinessChecks, postgresShadowParity: Boolean(shadow && postgres.dataReady) },
    ...baseHealth,
    postgres: { serverVersion: postgres.serverVersion ?? null, featureTableCount: postgres.featureTableCount ?? 0, dataReady: postgres.dataReady, missingObjects: postgres.missingObjects ?? [] },
    shadow: { postgres: shadow, parity: Boolean(shadow && postgres.dataReady) },
    readiness: postgresChecks?.readiness ?? null,
    persistence: 'planetscale-postgres',
    migration: { target: 'planetscale-postgres', stage: postgres.schemaReady && postgres.dataReady ? 'postgres-authority-active' : postgres.schemaReady ? 'schema-ready-awaiting-data-verification' : 'connectivity-probe' },
    authority: 'postgres',
    environment: env.ENVIRONMENT,
    workerVersion: '0.1.0',
  }, { status: options.readiness && !ok ? 503 : 200 });
}
