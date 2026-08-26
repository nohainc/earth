import { Client } from 'pg';
import { settleContinuousRankings } from '../cloudflare/src/engines/rankings-engine.ts';

export async function runRankingsCalculation({
  connectionString,
  environmentName = 'Database',
  isProduction = false,
}) {
  if (!connectionString) {
    throw new Error('DATABASE_URL is required to calculate rankings.');
  }

  const parsedConnection = new URL(connectionString);
  const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
  if (usesSystemRoot) {
    parsedConnection.searchParams.delete('sslrootcert');
    parsedConnection.searchParams.delete('sslmode');
  }

  console.log(`[Rankings Engine] Connecting to ${environmentName} (${parsedConnection.hostname})...`);

  const client = new Client({
    connectionString: parsedConnection.toString(),
    ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
    application_name: 'earth-rankings-calculator',
    connectionTimeoutMillis: 10000,
    query_timeout: 60000,
    statement_timeout: 60000,
  });

  await client.connect();

  try {
    // 1. Ensure civic_rankings table exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS civic_rankings (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        entity_name TEXT NOT NULL,
        rank INTEGER NOT NULL,
        rank_delta INTEGER NOT NULL DEFAULT 0,
        final_score INTEGER NOT NULL,
        metrics_line TEXT NOT NULL,
        sub_indexes JSONB NOT NULL DEFAULT '{}',
        raw_metrics JSONB NOT NULL DEFAULT '{}',
        affiliation TEXT,
        game_day INTEGER NOT NULL DEFAULT 1,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT uq_civic_rankings_entity UNIQUE (category, entity_id)
      );
      CREATE INDEX IF NOT EXISTS idx_civic_rankings_cat_score ON civic_rankings(category, final_score DESC, rank ASC);
    `);

    // 2. Fetch current world game day
    const worldRes = await client.query("SELECT game_day FROM world_state WHERE id = 'WORLD'").catch(() => ({ rows: [] }));
    const gameDay = Number(worldRes.rows[0]?.game_day ?? 184);

    console.log(`[Rankings Engine] Running relative data-driven settlement for Game Day ${gameDay}...`);

    // 3. Settle rankings
    const result = await settleContinuousRankings(client, gameDay);

    console.log(`[Rankings Engine] ✅ Settlement completed successfully:`);
    console.log(`   - Corporations Settled: ${result.corporationsSettled}`);
    console.log(`   - Cities Settled:       ${result.citiesSettled}`);
    console.log(`   - Citizens Settled:     ${result.citizensSettled}`);

    // 4. Print top 3 of each category
    const topCorps = await client.query("SELECT rank, entity_name, final_score, metrics_line FROM civic_rankings WHERE category = 'corporations' ORDER BY rank ASC LIMIT 3");
    const topCities = await client.query("SELECT rank, entity_name, final_score, metrics_line, affiliation FROM civic_rankings WHERE category = 'cities' ORDER BY rank ASC LIMIT 3");
    const topCitizens = await client.query("SELECT rank, entity_name, final_score, metrics_line, affiliation FROM civic_rankings WHERE category = 'citizens' ORDER BY rank ASC LIMIT 3");

    console.log('\n--- TOP CORPORATIONS ---');
    for (const row of topCorps.rows) {
      console.log(` #${row.rank} ${row.entity_name.padEnd(28)} Score: ${String(row.final_score).padStart(3)} | Metrics: ${row.metrics_line}`);
    }

    console.log('\n--- TOP CITIES ---');
    for (const row of topCities.rows) {
      console.log(` #${row.rank} ${row.entity_name.padEnd(20)} (${row.affiliation || 'Independent'}) Score: ${String(row.final_score).padStart(3)} | Metrics: ${row.metrics_line}`);
    }

    console.log('\n--- TOP CITIZENS ---');
    for (const row of topCitizens.rows) {
      console.log(` #${row.rank} ${row.entity_name.padEnd(20)} (${row.affiliation || 'Independent'}) Score: ${String(row.final_score).padStart(3)} | Metrics: ${row.metrics_line}`);
    }
    console.log('------------------------\n');

    return result;
  } finally {
    await client.end();
  }
}

// Allow direct CLI execution
if (import.meta.url === `file://${process.argv[1]}`) {
  const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
  await runRankingsCalculation({
    connectionString,
    environmentName: process.env.DATABASE_URL ? 'Custom Target' : 'Local Development',
  });
}
