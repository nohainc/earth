import { probePostgres } from './postgres';
import { withPostgresRepository } from './repository';

export async function healthResponse(request: Request, env: Env): Promise<Response> {
  const postgres = await probePostgres(env.HYPERDRIVE);
  const postgresChecks = await withPostgresRepository(env, async (repository) => {
    const [core, feature, reservations, governance, financial, assets, taxed, balances, scheduler, outbox, migrations, counts, settlement] = await Promise.all([
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state', 'humans', 'market_prices', 'account_balances', 'ledger_entries', 'ownership_events', 'membership_events']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['ai_assistants', 'buildings', 'civic_dividend_payouts', 'global_bank_deposits']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_quote_units'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['corporations', 'cities']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'personal_financial_states'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'buildings'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'buildings' AND column_name = 'daily_operating_credits'"),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
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
               completed.completed_at::text AS last_completed_at
        FROM daily_settlement_control control CROSS JOIN clock
        LEFT JOIN completed ON TRUE
        WHERE control.id = 'WORLD'
      `),
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
    const settlementBacklog = Number(settlementRow?.backlog_game_days ?? Number.POSITIVE_INFINITY);
    const settlementStatus = settlementRow?.status ?? 'unavailable';
    return {
      checks: {
        database: true,
        coreSchema: Number(core.rows[0]?.count ?? 0) === 8,
        featureSchema: Number(feature.rows[0]?.count ?? 0) === 4,
        marketCreditReservations: Number(reservations.rows[0]?.count ?? 0) === 1,
        businessGovernanceSchema: Number(governance.rows[0]?.count ?? 0) === 2,
        businessFinancialSchema: Number(financial.rows[0]?.count ?? 0) === 1,
        buildingAssetSchema: Number(assets.rows[0]?.count ?? 0) === 1,
        businessTaxSchema: Number(taxed.rows[0]?.count ?? 0) === 1,
        balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
        schedulerFresh: schedulerState !== 'critical',
        outboxPressure: outboxPending < 1000,
        outboxRetryFailures: outboxRetryFailures === 0,
        dailySettlementBacklog: settlementStatus !== 'active' || settlementBacklog <= 1,
        migrationManifest: Number(migrations.rows[0]?.version ?? 0) >= 33,
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
        dailySettlement: {
          status: settlementStatus,
          currentGameDay: settlementRow?.current_game_day != null ? Number(settlementRow.current_game_day) : null,
          lastCompletedGameDay: settlementRow?.last_completed_game_day != null ? Number(settlementRow.last_completed_game_day) : null,
          backlogGameDays: Number.isFinite(settlementBacklog) ? settlementBacklog : null,
          lastCompletedAt: settlementRow?.last_completed_at ?? null,
        },
        invariantScan: {
          ok: Number(balances.rows[0]?.invalid ?? 0) === 0,
          balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
        },
      },
      counts: {
        humans: Number(counts[0].rows[0]?.count ?? 0),
        privateBuildings: Number(counts[1].rows[0]?.count ?? 0),
        ledger: Number(counts[2].rows[0]?.count ?? 0),
        world: Number(counts[3].rows[0]?.count ?? 0),
      },
    };
  });
  const checks = postgresChecks?.checks ?? {
    database: false, coreSchema: false, featureSchema: false,
    marketCreditReservations: false, businessGovernanceSchema: false, businessFinancialSchema: false,
    buildingAssetSchema: false, businessTaxSchema: false, balancesNonNegative: false,
  };
  const shadow = postgresChecks?.counts ?? null;
  return Response.json({
    correlationId: request.headers.get('X-Request-ID') ?? crypto.randomUUID(),
    ok: Object.values(checks).every(Boolean),
    checks: { ...checks, postgresConfigured: postgres.configured, postgresReachable: postgres.reachable, postgresSchemaReady: postgres.schemaReady, postgresDataReady: postgres.dataReady, postgresShadowParity: Boolean(shadow && postgres.dataReady) },
    postgres: { serverVersion: postgres.serverVersion ?? null, featureTableCount: postgres.featureTableCount ?? 0, dataReady: postgres.dataReady },
    shadow: { postgres: shadow, parity: Boolean(shadow && postgres.dataReady) },
    readiness: postgresChecks?.readiness ?? null,
    persistence: 'planetscale-postgres',
    migration: { target: 'planetscale-postgres', stage: postgres.schemaReady && postgres.dataReady ? 'postgres-authority-active' : postgres.schemaReady ? 'schema-ready-awaiting-data-verification' : 'connectivity-probe' },
    authority: 'postgres',
    environment: env.ENVIRONMENT,
    workerVersion: '0.1.0',
  });
}
