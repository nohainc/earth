import { probePostgres } from './postgres';
import { withPostgresRepository } from './repository';

export async function healthResponse(request: Request, env: Env): Promise<Response> {
  const postgres = await probePostgres(env.HYPERDRIVE);
  const postgresChecks = await withPostgresRepository(env, async (repository) => {
    const [core, feature, maintenance, reservations, governance, financial, assets, taxed, balances, machines, scheduler, outbox, migrations, counts] = await Promise.all([
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['world_state', 'humans', 'market_prices', 'account_balances', 'ledger_entries', 'ownership_events', 'membership_events', 'authority_events']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['recycling_events', 'ai_assistants', 'machine_upgrade_events', 'machine_sales', 'production_events']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'maintenance_events' AND column_name = 'correlation_id'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'market_orders' AND column_name = 'reserved_credits'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)", [['business_constitutions', 'business_management']]),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_financials'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_assets'"),
      repository.query("SELECT COUNT(*)::integer AS count FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'business_financials' AND column_name = 'taxed_revenue'"),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM account_balances WHERE balance < 0'),
      repository.query('SELECT COUNT(*)::integer AS invalid FROM machines WHERE condition < 0 OR condition > 100'),
      repository.query("SELECT EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - last_scheduler_at)) AS age_seconds FROM world_state WHERE id = 'WORLD'"),
      repository.query("SELECT COUNT(*)::integer AS pending, COUNT(*) FILTER (WHERE attempts >= 5)::integer AS failed FROM event_outbox WHERE processed_at IS NULL AND available_at <= CURRENT_TIMESTAMP"),
      repository.query('SELECT COALESCE(MAX(version), 0)::integer AS version FROM earth_schema_migrations'),
      Promise.all([
        repository.query('SELECT COUNT(*)::integer AS count FROM humans'),
        repository.query('SELECT COUNT(*)::integer AS count FROM businesses'),
        repository.query('SELECT COUNT(*)::integer AS count FROM ledger_entries'),
        repository.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'"),
      ]),
    ]);
    const schedulerAgeSeconds = Number(scheduler.rows[0]?.age_seconds ?? Number.POSITIVE_INFINITY);
    const outboxPending = Number(outbox.rows[0]?.pending ?? 0);
    const outboxRetryFailures = Number(outbox.rows[0]?.failed ?? 0);
    return {
      checks: {
        database: true,
        coreSchema: Number(core.rows[0]?.count ?? 0) === 8,
        featureSchema: Number(feature.rows[0]?.count ?? 0) === 5,
        maintenanceIdempotency: Number(maintenance.rows[0]?.count ?? 0) === 1,
        marketCreditReservations: Number(reservations.rows[0]?.count ?? 0) === 1,
        businessGovernanceSchema: Number(governance.rows[0]?.count ?? 0) === 2,
        businessFinancialSchema: Number(financial.rows[0]?.count ?? 0) === 1,
        businessAssetSchema: Number(assets.rows[0]?.count ?? 0) === 1,
        businessTaxSchema: Number(taxed.rows[0]?.count ?? 0) === 1,
        balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
        machineConditionsBounded: Number(machines.rows[0]?.invalid ?? 0) === 0,
        schedulerFresh: schedulerAgeSeconds <= 900,
        outboxPressure: outboxPending < 1000,
        outboxRetryFailures: outboxRetryFailures === 0,
        migrationManifest: Number(migrations.rows[0]?.version ?? 0) === 17,
      },
      readiness: {
        schedulerAgeSeconds: Number.isFinite(schedulerAgeSeconds) ? schedulerAgeSeconds : null,
        outboxPending,
        outboxRetryFailures,
        migrationVersion: Number(migrations.rows[0]?.version ?? 0),
        invariantScan: {
          ok: Number(balances.rows[0]?.invalid ?? 0) === 0 && Number(machines.rows[0]?.invalid ?? 0) === 0,
          balancesNonNegative: Number(balances.rows[0]?.invalid ?? 0) === 0,
          machineConditionsBounded: Number(machines.rows[0]?.invalid ?? 0) === 0,
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
    database: false, coreSchema: false, featureSchema: false, maintenanceIdempotency: false,
    marketCreditReservations: false, businessGovernanceSchema: false, businessFinancialSchema: false,
    businessAssetSchema: false, businessTaxSchema: false, balancesNonNegative: false,
    machineConditionsBounded: false, migrationManifest: false,
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
