import { runClosedBetaSoak } from './run-closed-beta-soak.mjs';

const report = runClosedBetaSoak({
  seed: Number(process.env.EARTH_SOAK_SEED ?? 20260912),
  days: Number(process.env.EARTH_SOAK_DAYS ?? 365),
  houses: Number(process.env.EARTH_SOAK_HOUSES ?? 10_000),
  acceleration: Number(process.env.EARTH_SOAK_ACCELERATION ?? 24),
});

const failures = [];
if (!report.summary.creditConserved) failures.push('CREDIT supply diverged from authorized issuance');
if (!report.summary.nonNegative) failures.push('negative simulated wallet detected');
if (report.history.length !== report.config.days) failures.push('soak did not produce one result per game day');
if (failures.length) throw new Error(`Closed-beta soak certification failed:\n- ${failures.join('\n- ')}`);

console.log(JSON.stringify({
  ok: true,
  certification: 'closed-beta-soak',
  days: report.config.days,
  houses: report.config.houses,
  creditConserved: report.summary.creditConserved,
  nonNegative: report.summary.nonNegative,
  warnings: report.summary.warnings,
}, null, 2));
