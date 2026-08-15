import type { PostgresRepository } from './repository';
import { settleMarket } from './market-postgres';

const products = ['material', 'components', 'energy', 'compute'];

async function settleProduction(tx: PostgresRepository, day: number): Promise<number> {
  const machines = await tx.query<{ id: string; owner_id: string; business_id: string | null; productive_capacity: string; utilization: string; condition: string; output_resource: string; input_resource: string; input_per_output: string; focus: string }>("SELECT machines.id, machines.owner_id, business_assets.business_id, machines.productive_capacity, machines.utilization, machines.condition, machines.output_resource, machines.input_resource, machines.input_per_output, COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC, started_game_day DESC LIMIT 1), 'efficiency') AS focus FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id WHERE machines.condition > 0 AND machines.utilization > 0");
  let events = 0;
  for (const machine of machines.rows) {
    const outputFactor = machine.focus === 'efficiency' ? 1.1 : machine.focus === 'cost' ? 1 : 0.9;
    const inputFactor = machine.focus === 'cost' ? 0.85 : 1;
    const theoretical = Math.max(0, Number(machine.productive_capacity) * Number(machine.utilization) / 100 * Math.min(1, Number(machine.condition) / 100) * 2 * outputFactor);
    const input = await tx.query<{ amount: string }>('SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = $2 FOR UPDATE', [machine.owner_id, machine.input_resource]);
    const available = Number(input.rows[0]?.amount ?? 0);
    const perOutput = Number(machine.input_per_output) * inputFactor;
    const output = Math.round(Math.min(theoretical, perOutput > 0 ? available / perOutput : theoretical) * 100) / 100;
    const consumed = Math.round(output * perOutput * 100) / 100;
    if (output <= 0 || consumed <= 0) continue;
    const price = await tx.query<{ price: string }>('SELECT price FROM market_prices WHERE product = $1', [machine.input_resource]);
    const inputCost = Math.round(consumed * Number(price.rows[0]?.price ?? 0) * 100) / 100;
    await tx.query('UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = $3 AND amount >= $1', [consumed, machine.owner_id, machine.input_resource]);
    await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT(owner_id,resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [machine.owner_id, machine.output_resource, output]);
    const eventId = crypto.randomUUID();
    await tx.query('INSERT INTO production_events (id, machine_id, owner_id, resource, amount, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [eventId, machine.id, machine.owner_id, machine.output_resource, output, day]);
    if (machine.business_id) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [inputCost, day, machine.business_id]);
    events += 1;
  }
  return events;
}

export async function advanceWorld(repository: PostgresRepository, minutesPerTick = 5): Promise<{ day: number; minute: number; newDay: boolean; productionEvents: number; marketSettlements: number }> {
  const result = await repository.transaction(async (tx) => {
    const world = await tx.query<{ game_day: number; game_minute: number }>("SELECT game_day, game_minute FROM world_state WHERE id = 'WORLD' FOR UPDATE");
    const currentDay = Number(world.rows[0]?.game_day ?? 0);
    const currentMinute = Number(world.rows[0]?.game_minute ?? 0);
    const nextMinute = currentMinute + minutesPerTick;
    const newDay = nextMinute >= 1440;
    const day = currentDay + (newDay ? 1 : 0);
    const minute = nextMinute % 1440;
    await tx.query('UPDATE world_state SET game_day = $1, game_minute = $2 WHERE id = \'WORLD\'', [day, minute]);
    await tx.query("UPDATE role_assignments SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    await tx.query("UPDATE authority_delegations SET status = 'expired' WHERE status = 'active' AND ends_game_day <= $1", [day]);
    await tx.query("UPDATE machines SET condition = GREATEST(0, condition - GREATEST(0.05, utilization * 0.005 * CASE COALESCE((SELECT focus FROM research_projects WHERE owner_id = machines.owner_id AND status = 'active' ORDER BY progress DESC LIMIT 1), 'efficiency') WHEN 'durability' THEN 0.7 WHEN 'safety' THEN 0.8 ELSE 1 END)), maintenance_due = maintenance_due + GREATEST(1, utilization * 0.25)");
    await tx.query("UPDATE market_prices SET price = GREATEST(1, ROUND(price * (1 + LEAST(0.05, GREATEST(-0.05, (demand - supply) / GREATEST(1, supply + demand))))::numeric, 2)), game_day = $1", [day]);
    if (newDay) {
      await tx.query("UPDATE research_projects SET progress = LEAST(100, progress + CASE WHEN budget > 0 THEN 1 ELSE 0 END) WHERE status = 'active'");
      await tx.query("UPDATE technologies SET progress = LEAST(100, progress + CASE WHEN EXISTS (SELECT 1 FROM research_projects WHERE technology_id = technologies.id AND budget > 0 AND status = 'active') THEN 1 ELSE 0 END)");
      await tx.query("UPDATE cities SET housing_capacity = housing_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'housing' ORDER BY game_day DESC LIMIT 1), 0) / 1000), energy_capacity = energy_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'energy' ORDER BY game_day DESC LIMIT 1), 0) / 1000), connectivity_capacity = connectivity_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category = 'connectivity' ORDER BY game_day DESC LIMIT 1), 0) / 1000), health_capacity = health_capacity + LEAST(5, COALESCE((SELECT amount FROM budgets WHERE institution_id = cities.id AND category IN ('health','public-services','maintenance') ORDER BY game_day DESC LIMIT 1), 0) / 1000)");
      await tx.query('UPDATE budgets SET amount = GREATEST(0, amount - 100), game_day = $1 WHERE amount > 0', [day]);
      await tx.query("UPDATE humans SET age_years = age_years + 1, legacy = legacy + CASE WHEN standing > 0 THEN 1 ELSE 0 END WHERE life_status = 'active' AND $1 % 365 = 0", [day]);
    }
    await tx.query("UPDATE world_state SET living_cost_index = ROUND(GREATEST(0.5, LEAST(3, (SELECT COALESCE(AVG(price), 1) FROM market_prices) / 50))::numeric, 3), essential_services_index = ROUND(GREATEST(0, LEAST(1, (SELECT COALESCE(MIN(LEAST(1, housing_capacity / GREATEST(1, residents)), LEAST(1, energy_capacity / GREATEST(1, residents)), LEAST(1, connectivity_capacity / GREATEST(1, residents)), LEAST(1, health_capacity / 100.0)), 0) FROM cities)))::numeric, 3) WHERE id = 'WORLD'");
    await tx.query("UPDATE world_state SET health = CAST(GREATEST(0, LEAST(100, (SELECT COALESCE(AVG(condition), 68) FROM machines) * COALESCE(essential_services_index, 0.68))) AS INTEGER) WHERE id = 'WORLD'");
    await tx.query("INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,'world_clock','A new game tick begins',$3) ON CONFLICT (id) DO NOTHING", [`CLOCK-${day}-${minute}`, day, JSON.stringify({ newDay })]);
    const productionEvents = await settleProduction(tx, day);
    return { day, minute, newDay, productionEvents };
  });
  let marketSettlements = 0;
  for (const product of products) {
    const settled = await settleMarket(repository, product);
    if (settled.filled) marketSettlements += 1;
  }
  return { ...result, marketSettlements };
}
