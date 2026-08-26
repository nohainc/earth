import { runRankingsCalculation } from './calculate-rankings.mjs';

const connectionString = process.env.PRODUCTION_DATABASE_URL || process.env.DATABASE_URL;

if (!connectionString) {
  console.error('ERROR: PRODUCTION_DATABASE_URL (or DATABASE_URL) is required to calculate production rankings.');
  console.error('Usage: PRODUCTION_DATABASE_URL="postgres://user:pass@remote-host:5432/earth" node scripts/calculate-rankings-prod.mjs');
  process.exit(1);
}

const url = new URL(connectionString);
const isLocal = ['localhost', '127.0.0.1', '::1'].includes(url.hostname);

if (isLocal) {
  console.warn(`WARNING: Target hostname "${url.hostname}" appears to be a local database. Use scripts/calculate-rankings-local.mjs for local runs.`);
}

console.log('===> Starting Production Rankings Calculation <===');
await runRankingsCalculation({
  connectionString,
  environmentName: 'Production Postgres Database',
  isProduction: true,
});
