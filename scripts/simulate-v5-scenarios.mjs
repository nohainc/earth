import fs from 'node:fs';
import path from 'node:path';
import { runV5Simulation, V5_SCENARIOS } from '../simulation/v5-simulation-harness.mjs';

const REPORT_DIR = path.resolve('reports/simulation');
const REPORT_FILE = path.join(REPORT_DIR, 'v5-simulation-report.json');
const SUMMARY_FILE = path.join(REPORT_DIR, 'v5-simulation-summary.md');

if (!fs.existsSync(REPORT_DIR)) {
  fs.mkdirSync(REPORT_DIR, { recursive: true });
}

console.log('--- Starting V5 Multi-Scale & Scenario Simulation Matrix ---');

const scales = [100, 1000, 10000];
const scaleRuns = scales.map((h) => {
  console.log(`Running baseline scale benchmark for ${h} Houses...`);
  const days = h === 10000 ? 30 : 90;
  const start = Date.now();
  const res = runV5Simulation({ houses: h, days, seed: 42, scenario: 'baseline' });
  const durationMs = Date.now() - start;
  return { ...res, durationMs };
});

console.log('Running 16 canonical economic scenarios (100 Houses, 90 days)...');
const scenarioRuns = V5_SCENARIOS.map((sc) => {
  const start = Date.now();
  const res = runV5Simulation({ houses: 100, days: 90, seed: 42, scenario: sc });
  const durationMs = Date.now() - start;
  return { ...res, durationMs };
});

const reportPayload = {
  timestamp: new Date().toISOString(),
  version: 'V5-Economic-Core-Simulation-v1',
  scaleBenchmarks: scaleRuns,
  scenarios: scenarioRuns,
};

fs.writeFileSync(REPORT_FILE, JSON.stringify(reportPayload, null, 2), 'utf8');
console.log(`Saved JSON simulation report to ${REPORT_FILE}`);

// Write Markdown Summary
let md = `# V5 Economic Core Simulation Report
Generated: ${reportPayload.timestamp}

## 1. Scale Benchmarks
| Houses | Days | Duration (ms) | Survival Rate | Market Volume (Credits) | Earth Revenue | Gini |
|---|---|---|---|---|---|---|
`;

for (const run of scaleRuns) {
  md += `| ${run.houses} | ${run.days} | ${run.durationMs}ms | ${(run.survivalRate * 100).toFixed(1)}% | ${Math.round(run.marketVolume.creditVolume).toLocaleString()} | ${Math.round(run.earthRevenue).toLocaleString()} | ${run.concentration.gini.toFixed(3)} |\n`;
}

md += `\n## 2. Canonical Scenario Matrix (100 Houses, 90 Days)
| Scenario | Survival Rate | Trades | Earth Revenue | Specialization Advantage | Gini | Closing Material | Closing Energy | Closing Food |
|---|---|---|---|---|---|---|---|---|
`;

for (const run of scenarioRuns) {
  md += `| \`${run.scenario}\` | ${(run.survivalRate * 100).toFixed(1)}% | ${run.marketVolume.trades} | ${Math.round(run.earthRevenue).toLocaleString()} | ${run.specializationComparison.specializationAdvantageRatio.toFixed(2)}x | ${run.concentration.gini.toFixed(3)} | ${run.closingPrices.MATERIAL.toFixed(1)} | ${run.closingPrices.ENERGY.toFixed(1)} | ${run.closingPrices.FOOD.toFixed(1)} |\n`;
}

fs.writeFileSync(SUMMARY_FILE, md, 'utf8');
console.log(`Saved Markdown summary report to ${SUMMARY_FILE}`);
console.log('--- V5 Simulation Matrix Completed Successfully ---');
