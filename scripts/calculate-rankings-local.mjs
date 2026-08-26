import { runRankingsCalculation } from './calculate-rankings.mjs';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';

console.log('===> Starting Local Rankings Calculation <===');
await runRankingsCalculation({
  connectionString,
  environmentName: 'Local Postgres Database',
  isProduction: false,
});
