import { runResourceEconomySimulation } from '../simulation/resource-economy-simulator.mjs';

const horizons = [10, 30, 100];
const houses = Number(process.env.EARTH_CERT_HOUSES ?? 1000);
const scenario = process.env.EARTH_CERT_SCENARIO ?? 'baseline';
const cases = horizons.map((years) => {
  const result = runResourceEconomySimulation({ houses, days: years * 365, scenario, seed: houses * 31 + years });
  return { years, health: result.health, survivingHouses: result.survivingHouses, shortageFrequency: result.shortageFrequency, wealthConcentration: result.wealth.maxToMean, constructionStarted: result.constructionStarted };
});
const failures = cases.filter((item) => item.health.status !== 'HEALTHY');
const report = { ok: failures.length === 0, certification: 'earth-v4-long-horizon', deterministic: true, houses, scenario, horizons, cases, summary: { total: cases.length, healthy: cases.length - failures.length, review: failures.length } };
if (process.argv.includes('--json')) console.log(JSON.stringify(report)); else { console.log(`EARTH V4 LONG-HORIZON CERTIFICATION — ${houses} Houses / ${scenario}`); for (const item of cases) console.log(`${item.years} years: ${item.health.status}`); console.log(`Healthy ${report.summary.healthy}/${report.summary.total}`); }
if (failures.length) process.exitCode = 1;
