import { probePostgres } from './postgres';
import { withPostgresRepository } from './repository';

export async function healthResponse(request: Request, env: Env): Promise<Response> {
  const postgres = await probePostgres(env.HYPERDRIVE);
  const postgresChecks = await withPostgresRepository(env, async (repository) => {
    const [core, feature, reservations, governance, financial, assets, taxed, balances, scheduler, outbox, migrations, counts] = await Promise.all([
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state', 'humans', 'market_prices', 'account_balances', 'ledger_entries', 'ownership_events', 'membership_events', 'authority_events']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['ai_assistants', 'buildings', 'building_investment_shares', 'civic_dividend_payouts']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_credits'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['business_constitutions', 'business_management']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_financials'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'buildings'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'business_financials' AND column_name = 'taxed_revenue'"),
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
        repository.query('SELECT COUNT(*)::integer AS count FROM businesses'),
        repository.query('SELECT COUNT(*)::integer AS count FROM ledger_entries'),
        repository.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'"),
      ]),
    ]);
    const schedulerAgeSeconds = Number(scheduler.rows[0]?.age_seconds ?? Number.POSITIVE_INFINITY);
    const outboxRow = outbox.rows[0];
    const outboxPending = Number(outboxRow?.pending ?? 0);
    const outboxRetrying = Number(outboxRow?.retrying ?? 0);
    const outboxStaleLocks = Number(outboxRow?.stale_locks ?? 0);
    const outboxDeadLettered = Number(outboxRow?.dead_lettered ?? 0);
    const outboxRetryFailures = Number(outboxRow?.failed ?? 0);
    const outboxOldestAgeSeconds = outboxRow?.oldest_pending_age != null ? Number(outboxRow.oldest_pending_age) : null;
    const outboxLastDeliveryAt = outboxRow?.last_delivery ?? null;
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
        schedulerFresh: schedulerAgeSeconds <= 900,
        outboxPressure: outboxPending < 1000,
        outboxRetryFailures: outboxRetryFailures === 0,
        migrationManifest: Number(migrations.rows[0]?.version ?? 0) >= 33,
      },
      readiness: {
        schedulerAgeSeconds: Number.isFinite(schedulerAgeSeconds) ? schedulerAgeSeconds : null,
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
        invariantScan: {
          ok: Number(balances.rows[0]?.invalid ?? 0) === 0,
          balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
        },
      },
      counts: {
        humans: Number(counts[0].rows[0]?.count ?? 0),
        businesses: Number(counts[1].rows[0]?.count ?? 0),
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
