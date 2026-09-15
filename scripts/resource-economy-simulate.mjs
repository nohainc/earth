import { RESOURCE_SIMULATION_SCENARIOS, runResourceEconomySimulation } from '../simulation/resource-economy-simulator.mjs';

const args = new Map(process.argv.slice(2).filter((arg) => arg.startsWith('--')).map((arg) => {
  const [key, value = 'true'] = arg.slice(2).split('='); return [key, value];
}));
const populations = (args.get('houses') ?? '100,1000,10000').split(',').map(Number);
const horizons = (args.get('years') ?? '1,10,30,100').split(',').map((years) => Number(years) * 365);
const scenarios = args.get('scenario') ? [args.get('scenario')] : RESOURCE_SIMULATION_SCENARIOS;
const specialization = args.get('specialization') ?? 'mixed';
const results = [];
for (const houses of populations) for (const days of horizons) for (const scenario of scenarios) {
  results.push(runResourceEconomySimulation({ houses, days, scenario, specialization, seed: houses + days }));
}
if (args.get('json') === 'true') console.log(JSON.stringify(results));
else for (const result of results) console.log(`${result.houses} Houses / ${result.years} years / ${result.scenario}: ${result.health.status}, survival ${(result.survivingHouses / result.houses).toFixed(3)}, shortage ${(result.shortageFrequency * 100).toFixed(1)}%, utilization ${Object.entries(result.averageUtilization).map(([k, v]) => `${k} ${(v * 100).toFixed(0)}%`).join(' ')}, construction ${result.constructionStarted}, wealth ${result.wealth.maxToMean.toFixed(2)}x`);
