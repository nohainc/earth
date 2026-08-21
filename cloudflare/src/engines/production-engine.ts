import type { PostgresRepository } from '../repository.ts';

export interface ProductionRate {
  machineId: string;
  name: string;
  machineType: string;
  ownerId: string;
  inputResource: string;
  outputResource: string;
  inputRatePerSec: number;
  outputRatePerSec: number;
  conditionWearPerSec: number;
  condition: number;
  utilization: number;
  isActive: boolean;
}

export interface ProductionSettlementResult {
  settledEvents: number;
  machinesProcessed: number;
  totalOutput: Record<string, number>;
  totalConsumed: Record<string, number>;
}

export async function calculateMachineRates(repo: PostgresRepository, ownerId?: string): Promise<ProductionRate[]> {
  const query = ownerId
    ? 'SELECT * FROM machines WHERE owner_id = $1 AND condition > 0 AND utilization > 0'
    : 'SELECT * FROM machines WHERE condition > 0 AND utilization > 0';
  const params = ownerId ? [ownerId] : [];
  const machines = await repo.query<{
    id: string;
    name: string;
    machine_type: string;
    owner_id: string;
    condition: string;
    utilization: string;
    productive_capacity: string;
    input_resource: string;
    output_resource: string;
    input_per_output: string;
    focus: string;
  }>(query, params);

  const rates: ProductionRate[] = [];

  for (const m of machines.rows) {
    const condition = Number(m.condition ?? 0);
    const utilization = Number(m.utilization ?? 0);
    const capacity = Number(m.productive_capacity ?? 1.0);
    const inputPerOutput = Number(m.input_per_output ?? 1.0);

    const outputFactor = m.focus === 'efficiency' ? 1.1 : m.focus === 'cost' ? 1.0 : 0.9;
    const inputFactor = m.focus === 'cost' ? 0.85 : 1.0;

    // Daily theoretical output = Capacity * (Utilization / 100) * (Condition / 100) * 2 * outputFactor
    const dailyOutput = Math.max(0, capacity * (utilization / 100) * Math.min(1, condition / 100) * 2 * outputFactor);
    // Rate per second (1 game day = 1440 seconds in standard continuous simulation)
    const outputRatePerSec = dailyOutput / 1440;
    const inputRatePerSec = (outputRatePerSec * inputPerOutput) * inputFactor;
    // Condition drops ~0.05% per minute of active high utilization, scaled to per-second
    const conditionWearPerSec = (utilization * 0.0001) / 60;

    rates.push({
      machineId: m.id,
      name: m.name,
      machineType: m.machine_type,
      ownerId: m.owner_id,
      inputResource: m.input_resource,
      outputResource: m.output_resource,
      inputRatePerSec: Math.round(inputRatePerSec * 10000) / 10000,
      outputRatePerSec: Math.round(outputRatePerSec * 10000) / 10000,
      conditionWearPerSec: Math.round(conditionWearPerSec * 100000) / 100000,
      condition,
      utilization,
      isActive: condition > 0 && utilization > 0,
    });
  }

  return rates;
}

export async function settleContinuousProduction(
  repo: PostgresRepository,
  elapsedSeconds: number,
  gameDay: number,
): Promise<ProductionSettlementResult> {
  if (elapsedSeconds <= 0) {
    return { settledEvents: 0, machinesProcessed: 0, totalOutput: {}, totalConsumed: {} };
  }

  const rates = await calculateMachineRates(repo);
  let settledEvents = 0;
  const totalOutput: Record<string, number> = {};
  const totalConsumed: Record<string, number> = {};

  for (const rate of rates) {
    if (!rate.isActive) continue;

    const desiredConsumed = rate.inputRatePerSec * elapsedSeconds;
    if (desiredConsumed <= 0) continue;

    // Check available input inventory
    const inputRes = await repo.query<{ amount: string }>(
      'SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE',
      [rate.ownerId, rate.inputResource],
    );
    const available = Number(inputRes.rows[0]?.amount ?? 0);
    if (available <= 0) continue;

    const actualConsumed = Math.min(available, desiredConsumed);
    const ratio = actualConsumed / desiredConsumed;
    const actualOutput = Math.round(rate.outputRatePerSec * elapsedSeconds * ratio * 100) / 100;
    const actualWear = rate.conditionWearPerSec * elapsedSeconds;

    if (actualConsumed <= 0 || actualOutput <= 0) continue;

    // Deduct inputs and credit outputs
    await repo.query(
      'UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1',
      [actualConsumed, rate.ownerId, rate.inputResource],
    );
    await repo.query(
      'INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount',
      [rate.ownerId, rate.outputResource, actualOutput],
    );

    // Apply machine condition wear
    await repo.query(
      'UPDATE machines SET condition = GREATEST(0, condition - $1), maintenance_due = maintenance_due + $2 WHERE id = $3',
      [actualWear, Math.round(actualConsumed * 0.05), rate.machineId],
    );

    // Log production event
    await repo.query(
      'INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES ($1,$2,$3,$4,$5,$6)',
      [crypto.randomUUID(), rate.machineId, rate.ownerId, rate.outputResource, actualOutput, Math.floor(gameDay)],
    );

    totalConsumed[rate.inputResource] = (totalConsumed[rate.inputResource] ?? 0) + actualConsumed;
    totalOutput[rate.outputResource] = (totalOutput[rate.outputResource] ?? 0) + actualOutput;
    settledEvents += 1;
  }

  return {
    settledEvents,
    machinesProcessed: rates.length,
    totalOutput,
    totalConsumed,
  };
}
