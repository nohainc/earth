import { runSimulation } from '../simulation.js';

const scenarios = [
  { name: 'baseline-year', days: 365, humans: 30, seed: 42 },
  { name: 'small-community', days: 180, humans: 5, seed: 7 },
  { name: 'large-world', days: 365, humans: 250, seed: 2026 },
  { name: 'long-generation', days: 1825, humans: 100, seed: 99 },
];

const results = scenarios.map((scenario) => ({
  ...scenario,
  result: runSimulation(scenario),
}));

for (const { name, result } of results) {
  const checks = [
    result.creditsConserved,
    result.nonNegativeBalances,
    result.resourceNonNegative,
    result.institutionBalancesNonNegative,
    result.boundedMachineCondition,
  ];
  if (!checks.every(Boolean)) throw new Error(`Simulation invariant failed in ${name}`);
}

console.log(JSON.stringify(results.map(({ name, result }) => ({
  name,
  days: result.days,
  humans: result.humans,
  trades: result.trades,
  production: result.production,
  fees: result.fees,
  creditsConserved: result.creditsConserved,
  nonNegativeBalances: result.nonNegativeBalances,
  resourceNonNegative: result.resourceNonNegative,
  institutionBalancesNonNegative: result.institutionBalancesNonNegative,
  boundedMachineCondition: result.boundedMachineCondition,
})), null, 2));
