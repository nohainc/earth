import { RESOURCE_SIMULATION_SCENARIOS, runResourceEconomySimulation } from '../simulation/resource-economy-simulator.mjs';

const args = new Map(process.argv.slice(2).filter((arg) => arg.startsWith('--')).map((arg) => {
  const [key, value = 'true'] = arg.slice(2).split('='); return [key, value];
}));
const populations = (args.get('houses') ?? '100,1000,10000').split(',').map(Number);
const years = (args.get('years') ?? '10,30,100').split(',').map(Number);
const scenarios = (args.get('scenario') ? [args.get('scenario')] : RESOURCE_SIMULATION_SCENARIOS);
const results = [];
for (const houses of populations) for (const horizon of years) for (const scenario of scenarios) {
  const result = runResourceEconomySimulation({ houses, days: horizon * 365, scenario, seed: houses * 31 + horizon });
  results.push({ houses, years: horizon, scenario, health: result.health, survivingHouses: result.survivingHouses, shortageFrequency: result.shortageFrequency, wealthConcentration: result.wealth.maxToMean, constructionStarted: result.constructionStarted });
}
const failed = results.filter((result) => result.health.status !== 'HEALTHY');
const report = { lab: 'earth-v4-long-horizon', deterministic: true, populations, years, scenarios, results, summary: { cases: results.length, healthyCases: results.length - failed.length, reviewCases: failed.length } };
if (args.get('json') === 'true') console.log(JSON.stringify(report));
else {
  console.log(`EARTH V4 BALANCE LAB — ${results.length} deterministic cases`);
  for (const result of results) console.log(`${result.houses} Houses / ${result.years} years / ${result.scenario}: ${result.health.status}`);
  console.log(`Healthy ${report.summary.healthyCases} · Review ${report.summary.reviewCases}`);
}
