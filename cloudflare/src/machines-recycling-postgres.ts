import type { PostgresRepository } from './repository';

export async function recycleMachine(repository: PostgresRepository, input: { machineId: string; ownerId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const machine = await tx.query<{ id: string; machine_type: string; condition: string; productive_capacity: string }>('SELECT id, machine_type, condition, productive_capacity FROM machines WHERE id = $1 AND owner_id = $2 FOR UPDATE', [input.machineId, input.ownerId]);
    if (!machine.rows[0]) throw new Error('Machine not found for this Human');
    const embeddedMaterial: Record<string, number> = { extractor: 80, 'energy-array': 60, 'compute-node': 100, fabricator: 90, 'housing-fabricator': 110, 'research-cluster': 140, 'service-robot': 45 };
    const efficiency = Math.min(0.8, Math.max(0.2, 0.25 + Number(machine.rows[0].condition ?? 0) / 200));
    const materialReturned = Math.round((embeddedMaterial[machine.rows[0].machine_type] ?? 60) * efficiency * 100) / 100;
    const componentsReturned = Math.round((Number(machine.rows[0].productive_capacity ?? 1) * 25 * efficiency) * 100) / 100;
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const eventId = crypto.randomUUID();
    await tx.query('DELETE FROM business_assets WHERE machine_id = $1', [input.machineId]);
    await tx.query('DELETE FROM machines WHERE id = $1 AND owner_id = $2', [input.machineId, input.ownerId]);
    await tx.query("INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1, 'material', $2), ($1, 'components', $3) ON CONFLICT(owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount", [input.ownerId, materialReturned, componentsReturned]);
    await tx.query('INSERT INTO recycling_events (id, machine_id, owner_id, material_returned, components_returned, efficiency, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7)', [eventId, input.machineId, input.ownerId, materialReturned, componentsReturned, efficiency, day]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'MACHINE', input.machineId, input.ownerId, null, 1, 'recycling', eventId, day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'production', 'Machine recycled', `${materialReturned} Material and ${componentsReturned} Components returned at ${Math.round(efficiency * 100)}% efficiency.`, input.machineId]);
    return { ok: true, eventId, machineId: input.machineId, materialReturned, componentsReturned, efficiency };
  });
}
