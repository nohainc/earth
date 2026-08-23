import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, moneyToCents } from './money';
import { MACHINE_CATALOG } from './production-catalog';

type MachineInput = { id: string; owner_id: string; condition: string; maintenance_due: string; name: string; productive_capacity: string; utilization: string };

export async function acquireMachine(repository: PostgresRepository, input: { ownerId: string; machineType: string; name: string; credit: number; material: number; capacity: number; output: string; inputResource: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>("SELECT reason_id FROM ledger_entries WHERE reason_type = 'machine_acquisition' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [prior.rows[0].reason_id])).rows[0], acquisitionId: input.correlationId };
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [input.ownerId]);
    const material = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'material' FOR UPDATE", [input.ownerId]);
    const creditCents = moneyToCents(input.credit);
    const credit = centsToMoney(creditCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < creditCents) throw new Error('Insufficient Credits for machine acquisition');
    if (!material.rows[0] || Number(material.rows[0].amount) < input.material) throw new Error('Insufficient Material for machine acquisition');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const machineId = `M-${input.ownerId}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-machine-registry', amount: credit, reasonType: 'machine_acquisition', reasonId: machineId, ruleVersion: 'machine-v3', correlationId: input.correlationId });
    const debitedMaterial = await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'material' AND amount >= $1", [input.material, input.ownerId]);
    if (debitedMaterial.rowCount !== 1) throw new Error('Machine acquisition material reservation failed');
    const inputPerOutput = MACHINE_CATALOG[input.machineType]?.inputPerOutput ?? 0.25;
    await tx.query('INSERT INTO machines (id, owner_id, name, machine_type, condition, utilization, maintenance_due, productive_capacity, output_resource, input_resource, input_per_output) VALUES ($1,$2,$3,$4,100,25,0,$5,$6,$7,$8)', [machineId, input.ownerId, input.name, input.machineType, input.capacity, input.output, input.inputResource, inputPerOutput]);
    // Acquired machines remain personal work units until the player chooses
    // a workplace. This matters once a Human owns more than one business.
    await tx.query('INSERT INTO machine_acquisitions (id, machine_id, owner_id, machine_type, credit_cost, material_cost, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7)', [input.correlationId, machineId, input.ownerId, input.machineType, credit, input.material, day]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'MACHINE', machineId, null, input.ownerId, 1, 'machine_acquisition', input.correlationId, day]);
    return { ok: true, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [machineId])).rows[0], acquisitionId: input.correlationId };
  });
}

export async function maintainMachine(repository: PostgresRepository, input: { machineId: string; ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const existing = await tx.query<{ id: string; amount: string; game_day: number }>('SELECT id, amount, game_day FROM maintenance_events WHERE machine_id = $1 AND correlation_id = $2', [input.machineId, input.correlationId]);
    if (existing.rows[0]) return { ok: true, alreadyProcessed: true, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], eventId: existing.rows[0].id, amount: Number(existing.rows[0].amount), gameDay: existing.rows[0].game_day, correlationId: input.correlationId };
    const machine = await tx.query<MachineInput>('SELECT id, owner_id, condition, maintenance_due, name, productive_capacity, utilization FROM machines WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.machineId, input.ownerId]);
    if (!machine.rows[0]) throw new Error('Machine not found for this Human');
    const components = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE", [input.ownerId]);
    if (!components.rows[0] || Number(components.rows[0].amount) < input.amount) throw new Error('Insufficient Components for maintenance');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const before = Number(machine.rows[0].condition);
    const after = Math.min(100, before + input.amount * 0.8);
    const price = await tx.query<{ price: string }>("SELECT price FROM market_prices WHERE product = 'components'");
    const maintenanceCost = Math.round(input.amount * Number(price.rows[0]?.price ?? 0) * 100) / 100;
    const debited = await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components' AND amount >= $1", [input.amount, input.ownerId]);
    if (debited.rowCount !== 1) throw new Error('Maintenance component reservation failed');
    await tx.query('UPDATE machines SET condition = $1, maintenance_due = GREATEST(0, maintenance_due - $2) WHERE id = $3 AND owner_id = $4', [after, input.amount, input.machineId, input.ownerId]);
    const eventId = crypto.randomUUID();
    await tx.query('INSERT INTO maintenance_events (id, machine_id, owner_id, resource, amount, condition_before, condition_after, game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [eventId, input.machineId, input.ownerId, 'components', input.amount, before, after, gameDay, input.correlationId]);
    const asset = await tx.query<{ business_id: string }>('SELECT business_id FROM business_assets WHERE machine_id = $1', [input.machineId]);
    if (asset.rows[0]) await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $2, last_game_day = $3, updated_at = CURRENT_TIMESTAMP WHERE business_id = $4', [maintenanceCost, maintenanceCost, gameDay, asset.rows[0].business_id]);
    return { ok: true, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], eventId, amount: input.amount, gameDay, correlationId: input.correlationId };
  });
}

export async function setMachineUtilization(repository: PostgresRepository, input: { machineId: string; ownerId: string; utilization: number }): Promise<Record<string, unknown>> {
  const result = await repository.query('UPDATE machines SET utilization = $1 WHERE id = $2 AND owner_id = $3 RETURNING *', [input.utilization, input.machineId, input.ownerId]);
  if (!result.rows[0]) throw new Error('Machine not found for this Human');
  return { ok: true, machine: result.rows[0] };
}

export async function assignMachineToBusiness(repository: PostgresRepository, input: { machineId: string; ownerId: string; businessId: string | null }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const machine = await tx.query<{ id: string }>('SELECT id FROM machines WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.machineId, input.ownerId]);
    if (!machine.rows[0]) throw new Error('Machine not found for this Human');
    if (input.businessId) {
      const business = await tx.query<{ id: string }>(`SELECT b.id FROM businesses b LEFT JOIN business_management bm ON bm.business_id = b.id WHERE b.id = $1 AND b.status = 'active' AND (b.owner_id = $2 OR bm.manager_id = $2 OR EXISTS (SELECT 1 FROM business_shares bs WHERE bs.business_id = b.id AND bs.holder_id = $2))`, [input.businessId, input.ownerId]);
      if (!business.rows[0]) throw new Error('Business workplace access denied');
      await tx.query("INSERT INTO business_assets (business_id, machine_id, assigned_game_day, assigned_by) SELECT $1, $2, game_day, $3 FROM world_state WHERE id = 'WORLD' ON CONFLICT (machine_id) DO UPDATE SET business_id = EXCLUDED.business_id, assigned_game_day = EXCLUDED.assigned_game_day, assigned_by = EXCLUDED.assigned_by", [input.businessId, input.machineId, input.ownerId]);
    } else {
      await tx.query('DELETE FROM business_assets WHERE machine_id = $1', [input.machineId]);
    }
    const result = await tx.query('SELECT machines.*, business_assets.business_id, businesses.name AS business_name FROM machines LEFT JOIN business_assets ON business_assets.machine_id = machines.id LEFT JOIN businesses ON businesses.id = business_assets.business_id WHERE machines.id = $1', [input.machineId]);
    return { ok: true, machine: result.rows[0] };
  });
}

export async function upgradeMachine(repository: PostgresRepository, input: { machineId: string; ownerId: string; correlationId: string; creditCost: number; componentsCost: number }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const membership = await tx.query<{ city_id: string | null }>('SELECT city_id FROM memberships WHERE human_id = $1 FOR UPDATE', [input.ownerId]);
    if (!membership.rows[0]?.city_id) {
      throw new Error('Machine upgrades require an active city affiliation');
    }
    const technologyAccess = await tx.query(
      `SELECT 1
       FROM research_projects
       WHERE owner_id = $1 AND progress >= 100
       UNION ALL
       SELECT 1
       FROM corporation_technology_shares share
       JOIN memberships member ON member.corporation_id = share.corporation_id
         AND member.human_id = $1
       JOIN patents ON patents.id = share.patent_id AND patents.status = 'active'
       WHERE share.status = 'active'
       LIMIT 1`,
      [input.ownerId],
    );
    if (!technologyAccess.rows[0]) {
      throw new Error('Machine upgrades require a completed city research project or corporation technology');
    }
    const prior = await tx.query<{ id: string }>("SELECT id FROM ledger_entries WHERE reason_type = 'machine_upgrade' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, eventId: prior.rows[0].id, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], correlationId: input.correlationId };
    const machine = await tx.query<{ id: string; name: string; productive_capacity: string }>('SELECT id, name, productive_capacity FROM machines WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.machineId, input.ownerId]);
    if (!machine.rows[0]) throw new Error('Machine not found for this Human');
    const capacityBefore = Number(machine.rows[0].productive_capacity ?? 1);
    if (capacityBefore >= 5) throw new Error('Machine has reached the engine upgrade ceiling');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    const components = await tx.query<{ amount: string }>("SELECT amount FROM resource_balances WHERE owner_id = $1 AND resource = 'components' FOR UPDATE", [input.ownerId]);
    if (!account.rows[0] || Number(account.rows[0].balance) < input.creditCost) throw new Error('Insufficient Credits for machine upgrade');
    if (!components.rows[0] || Number(components.rows[0].amount) < input.componentsCost) throw new Error('Insufficient Components for machine upgrade');
    const capacityAfter = Math.min(5, Math.round((capacityBefore + 0.2) * 100) / 100);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const transfer = await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay: day,
      debitAccount: account.rows[0].account_id,
      creditAccount: 'account-ouc-treasury',
      amount: input.creditCost,
      reasonType: 'machine_upgrade',
      reasonId: input.machineId,
      ruleVersion: 'machine-v3',
      correlationId: input.correlationId,
    });
    if (transfer.status === 'already_processed') return { ok: true, alreadyProcessed: true, eventId: prior.rows[0]?.id ?? transfer.ledgerId, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], correlationId: input.correlationId };
    const debitedComponents = await tx.query("UPDATE resource_balances SET amount = amount - $1 WHERE owner_id = $2 AND resource = 'components' AND amount >= $1", [input.componentsCost, input.ownerId]);
    if (debitedComponents.rowCount !== 1) throw new Error('Machine upgrade resource reservation failed');
    await tx.query('UPDATE machines SET productive_capacity = $1, condition = GREATEST(0, condition - 5) WHERE id = $2 AND owner_id = $3', [capacityAfter, input.machineId, input.ownerId]);
    const eventId = crypto.randomUUID();
    await tx.query('INSERT INTO machine_upgrade_events (id, machine_id, owner_id, credit_cost, components_cost, capacity_before, capacity_after, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', [eventId, input.machineId, input.ownerId, input.creditCost, input.componentsCost, capacityBefore, capacityAfter, day]);
    return { ok: true, eventId, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], creditCost: input.creditCost, componentsCost: input.componentsCost, correlationId: input.correlationId };
  });
}

export async function sellMachine(repository: PostgresRepository, input: { machineId: string; sellerId: string; buyerId: string; price: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string; machine_id: string; buyer_id: string; price: string }>("SELECT id, machine_id, buyer_id, price FROM machine_sales WHERE id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, saleId: prior.rows[0].id, machineId: prior.rows[0].machine_id, buyerId: prior.rows[0].buyer_id, price: Number(prior.rows[0].price), correlationId: input.correlationId };
    if (input.sellerId === input.buyerId) throw new Error('A Human cannot sell a machine to themselves');
    const buyer = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.buyerId]);
    if (!buyer.rows[0]) throw new Error('Active buyer not found');
    const machine = await tx.query<{ id: string; owner_id: string; name: string }>('SELECT id, owner_id, name FROM machines WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.machineId, input.sellerId]);
    if (!machine.rows[0]) throw new Error('Machine not found for this Human');
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id", [input.sellerId, input.buyerId]);
    const buyerAccount = accounts.rows.find((row) => row.owner_id === input.buyerId);
    const sellerAccount = accounts.rows.find((row) => row.owner_id === input.sellerId);
    const priceCents = moneyToCents(input.price);
    const price = centsToMoney(priceCents);
    if (!buyerAccount || !sellerAccount) throw new Error('Active buyer and seller accounts are required');
    if (moneyToCents(buyerAccount.balance) < priceCents) throw new Error('Buyer has insufficient Credits');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const saleId = input.correlationId;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: buyerAccount.account_id, creditAccount: sellerAccount.account_id, amount: price, reasonType: 'machine_sale', reasonId: input.machineId, ruleVersion: 'machine-v4', correlationId: saleId });
    await tx.query('UPDATE machines SET owner_id = $1 WHERE id = $2 AND owner_id = $3', [input.buyerId, input.machineId, input.sellerId]);
    await tx.query('DELETE FROM business_assets WHERE machine_id = $1', [input.machineId]);
    // A secondary-market purchase also stays in personal inventory until
    // the buyer explicitly assigns it to a business.
    await tx.query('INSERT INTO machine_sales (id, machine_id, seller_id, buyer_id, price, game_day) VALUES ($1,$2,$3,$4,$5,$6)', [saleId, input.machineId, input.sellerId, input.buyerId, price, day]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'MACHINE', input.machineId, input.sellerId, input.buyerId, 1, 'secondary_sale', saleId, day]);
    return { ok: true, saleId, machineId: input.machineId, buyerId: input.buyerId, price: Number(price), day, machine: (await tx.query('SELECT * FROM machines WHERE id = $1', [input.machineId])).rows[0], correlationId: saleId };
  });
}
