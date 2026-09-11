import { ECONOMY_SIMULATION_PROFILES, runEconomySimulation } from '../simulation.js';

const args = new Map(process.argv.slice(2).filter((arg) => arg.startsWith('--')).map((arg) => {
  const [key, value = 'true'] = arg.slice(2).split('=');
  return [key, value];
}));
const profile = args.get('profile') ?? 'small';
const houses = Number(args.get('houses') ?? ECONOMY_SIMULATION_PROFILES[profile]);
const days = Number(args.get('days') ?? 365);
const seed = Number(args.get('seed') ?? 42);
const requestedScenarios = args.get('scenario') ? [args.get('scenario')] : Object.keys({
  baseline: true, 'high-energy-shortage': true, 'high-food-demand': true,
  'low-taxes': true, 'high-taxes': true, 'technology-heavy': true, 'rapid-construction': true,
});
if (!Number.isInteger(houses) || houses < 1) throw new Error('Use --houses=<positive integer> or a known --profile.');
if (!Number.isInteger(days) || days < 1) throw new Error('--days must be a positive integer.');

const results = requestedScenarios.map((scenario, index) => runEconomySimulation({ days, houses, seed: seed + index, scenario }));
if (args.get('json') === 'true') {
  console.log(JSON.stringify(results, null, 2));
} else {
  console.log(`ECONOMY SIMULATION — ${profile} (${houses.toLocaleString()} Houses, ${days} game days)`);
  console.log('This is a deterministic instability detector, not a forecast.\n');
  for (const result of results) {
    console.log(`${result.scenario}`);
    console.log(`  CREDIT supply: ${result.issuedCredits.toLocaleString()} → ${result.closingCreditSupply.toLocaleString()} (conserved: ${result.creditConserved})`);
    console.log(`  Resources: ${Object.entries(result.resources).map(([key, value]) => `${key} ${Math.round(value).toLocaleString()}`).join(' | ')}`);
    console.log(`  Prices: ${Object.entries(result.prices).map(([key, value]) => `${key} ${value.toFixed(2)}`).join(' | ')}`);
    console.log(`  Trades ${result.totalTrades.toLocaleString()} | tax revenue ${Math.round(result.taxRevenue).toLocaleString()} | research completions ${result.completedResearch.toLocaleString()}`);
    console.log(`  Shortage ${Math.round(result.totalShortage).toLocaleString()} | wealth concentration ${result.wealthDistribution.concentrationRatio.toFixed(2)}x`);
    for (const warning of result.warnings) console.log(`  WARNING: ${warning}`);
    console.log('');
  }
}
