import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';

export const SCALE_STAGES = [1_000, 10_000, 100_000, 1_000_000];

export function syntheticWorld(houses) {
  const humans = houses;
  const buildings = Math.round(houses * 1.8);
  const cities = Math.max(1, Math.round(houses / 250));
  const corporations = Math.max(1, Math.round(houses / 100));
  return {
    houses, humans, buildings, cities, corporations,
    marketOrders: Math.round(houses * 0.35),
    economicTransactions: Math.round(houses * 5.5),
    notifications: Math.round(houses * 2.2),
    researchProjects: Math.round(corporations * 1.2),
  };
}

function runSettlement(world, withRepairBookkeeping) {
  let checksum = 0;
  for (let id = 0; id < world.buildings; id += 1) {
    const condition = withRepairBookkeeping ? 100 - (id % 101) : 100;
    const wear = withRepairBookkeeping ? (id % 7) : 0;
    const repair = withRepairBookkeeping ? Math.min(100 - condition + wear, id % 5) : 0;
    let state = condition - wear + repair + id % 11;
    if (withRepairBookkeeping) {
      // Model the removed V1 bookkeeping work: condition curve, wear,
      // repair eligibility and status transitions are deliberately measured
      // separately from the operation-only V2 path.
      for (let step = 0; step < 8; step += 1) state = Math.max(0, Math.min(100, state - (id + step) % 3 + (id + step) % 2));
    }
    checksum += state | 0;
  }
  return checksum;
}

export function benchmarkStage(houses) {
  const world = syntheticWorld(houses);
  const before = process.memoryUsage().heapUsed;
  const streamlinedStart = performance.now();
  const streamlinedChecksum = runSettlement(world, false);
  const streamlinedMs = performance.now() - streamlinedStart;
  const repairStart = performance.now();
  const repairChecksum = runSettlement(world, true);
  const repairBookkeepingMs = performance.now() - repairStart;
  const after = process.memoryUsage().heapUsed;
  return {
    ...world,
    streamlinedMs: Number(streamlinedMs.toFixed(3)),
    repairBookkeepingMs: Number(repairBookkeepingMs.toFixed(3)),
    repairOverheadRatio: Number((repairBookkeepingMs / Math.max(streamlinedMs, 0.001)).toFixed(3)),
    heapDeltaMb: Number(((after - before) / 1024 / 1024).toFixed(3)),
    checksums: { streamlined: streamlinedChecksum, repairBookkeeping: repairChecksum },
  };
}

export function runScaleBenchmark(stages = SCALE_STAGES) {
  return stages.map(benchmarkStage);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const maxHouses = Number(process.env.EARTH_SCALE_MAX_HOUSES ?? 1_000_000);
  const stages = SCALE_STAGES.filter((stage) => stage <= maxHouses);
  console.log(JSON.stringify({ benchmark: 'economy-v2-scale', stages: runScaleBenchmark(stages) }, null, 2));
}
