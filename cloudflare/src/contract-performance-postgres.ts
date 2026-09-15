import type { PostgresRepository } from './repository.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';

async function currentDay(tx: PostgresRepository): Promise<number> { return Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1); }

export async function listContractPerformance(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const rows = await repository.query(`SELECT p.id, p.contract_id, c.buyer_organization_id, c.seller_organization_id, p.period_start_game_day, p.period_end_game_day, p.status, p.obligation_id, p.dispute_reason, p.delivered_game_day, p.delivery_note, p.delivered_units, p.quality_score_bps, p.accepted_game_day, p.resolution_action, p.resolution_reason, p.resolved_game_day
    FROM contract_performance_events p JOIN organization_contracts c ON c.id = p.contract_id
    WHERE c.buyer_organization_id = $1 OR c.seller_organization_id = $1 ORDER BY p.period_end_game_day DESC, p.id`, [organizationId]);
  return { organizationId, performance: rows.rows, generatedFrom: 'postgres-canonical-facts' };
}

async function updatePerformance(repository: PostgresRepository, input: { organizationId: string; performanceId: string; humanId: string; correlationId: string; action: 'DELIVER' | 'ACCEPT' | 'REJECT' | 'RESOLVE'; note?: string; units?: string; qualityBps?: number; resolution?: 'ACCEPTED' | 'FAILED' | 'WAIVED' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM contract_performance_events WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, performanceId: prior.rows[0].id, correlationId: input.correlationId };
    const row = (await tx.query<{ id: string; status: string; contract_id: string; buyer_organization_id: string; seller_organization_id: string }>(`SELECT p.id, p.status, p.contract_id, c.buyer_organization_id, c.seller_organization_id FROM contract_performance_events p JOIN organization_contracts c ON c.id = p.contract_id WHERE p.id = $1 AND (c.buyer_organization_id = $2 OR c.seller_organization_id = $2) FOR UPDATE`, [input.performanceId, input.organizationId])).rows[0];
    if (!row) throw new Error('Performance event is unavailable to this Organization');
    const requiredParty = input.action === 'DELIVER' ? row.seller_organization_id : row.buyer_organization_id;
    if (input.action !== 'RESOLVE' && input.organizationId !== requiredParty) throw new Error(`${input.action === 'DELIVER' ? 'Seller' : 'Buyer'} Organization authority is required`);
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: input.action === 'DELIVER' ? 'ORGANIZATION_OPERATE' : 'GOVERNANCE' });
    const day = await currentDay(tx);
    if (input.action === 'DELIVER') {
      if (row.status !== 'DUE' || !input.note?.trim()) throw new Error('Only due performance events can be delivered, with a delivery note');
      const units = BigInt(input.units ?? '0');
      if (units < 0n || input.qualityBps === undefined || !Number.isInteger(input.qualityBps) || input.qualityBps < 0 || input.qualityBps > 10000) throw new Error('Delivery units and quality score are invalid');
      await tx.query("UPDATE contract_performance_events SET status = 'DELIVERED', delivered_game_day = $2, delivery_note = $3, delivered_units = $4, quality_score_bps = $5 WHERE id = $1", [row.id, day, input.note.trim(), units.toString(), input.qualityBps]);
    } else if (input.action === 'ACCEPT' || input.action === 'REJECT') {
      if (row.status !== 'DELIVERED') throw new Error('Only delivered performance events can be accepted or rejected');
      await tx.query("UPDATE contract_performance_events SET status = $2, accepted_game_day = $3, resolution_action = $2, resolution_reason = $4, resolved_by_human_id = $5, resolved_game_day = $3 WHERE id = $1", [row.id, input.action === 'ACCEPT' ? 'ACCEPTED' : 'FAILED', day, input.note?.trim() ?? null, input.humanId]);
    } else {
      if (row.status !== 'DISPUTED' || !input.resolution || !input.note?.trim()) throw new Error('A disputed event requires a resolution and reason');
      await tx.query('UPDATE contract_performance_events SET status = $2, resolution_action = $2, resolution_reason = $3, resolved_by_human_id = $4, resolved_game_day = $5 WHERE id = $1', [row.id, input.resolution, input.note.trim(), input.humanId, day]);
    }
    await createGameEvent(tx, { id: `CONTRACT-PERFORMANCE-${input.action}-${row.id}-${input.correlationId}`, category: 'INSTITUTION', eventType: `ORGANIZATION_CONTRACT_${input.action === 'DELIVER' ? 'DELIVERY_SUBMITTED' : input.action === 'ACCEPT' ? 'DELIVERY_ACCEPTED' : input.action === 'REJECT' ? 'DELIVERY_REJECTED' : 'DISPUTE_RESOLVED'}`, gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: `Contract performance ${input.action.toLowerCase()}`, details: { performanceId: row.id, contractId: row.contract_id, reason: input.note?.trim() ?? null, resolution: input.resolution ?? null }, correlationId: input.correlationId });
    return { ok: true, performanceId: row.id, status: input.action === 'DELIVER' ? 'DELIVERED' : input.action === 'ACCEPT' ? 'ACCEPTED' : input.action === 'REJECT' ? 'FAILED' : input.resolution, correlationId: input.correlationId };
  });
}

export const submitContractDelivery = (repository: PostgresRepository, input: Omit<Parameters<typeof updatePerformance>[1], 'action'>) => updatePerformance(repository, { ...input, action: 'DELIVER' });
export const acceptContractDelivery = (repository: PostgresRepository, input: Omit<Parameters<typeof updatePerformance>[1], 'action'>) => updatePerformance(repository, { ...input, action: 'ACCEPT' });
export const rejectContractDelivery = (repository: PostgresRepository, input: Omit<Parameters<typeof updatePerformance>[1], 'action'>) => updatePerformance(repository, { ...input, action: 'REJECT' });
export const resolveContractDispute = (repository: PostgresRepository, input: Omit<Parameters<typeof updatePerformance>[1], 'action'>) => updatePerformance(repository, { ...input, action: 'RESOLVE' });

export async function disputeContractPerformance(repository: PostgresRepository, input: { organizationId: string; performanceId: string; reason: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM contract_performance_events WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, performanceId: prior.rows[0].id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'ORGANIZATION_OPERATE' });
    if (!input.reason.trim() || input.reason.length > 1000) throw new Error('A concise delivery dispute reason is required');
    const row = (await tx.query<{ id: string; status: string; contract_id: string }>(`SELECT p.id, p.status, p.contract_id FROM contract_performance_events p JOIN organization_contracts c ON c.id = p.contract_id WHERE p.id = $1 AND (c.buyer_organization_id = $2 OR c.seller_organization_id = $2) FOR UPDATE`, [input.performanceId, input.organizationId])).rows[0];
    if (!row || !['DUE', 'DELIVERED', 'PERFORMED', 'FAILED'].includes(row.status)) throw new Error('Performance event is not disputable');
    const day = await currentDay(tx);
    await tx.query("UPDATE contract_performance_events SET status = 'DISPUTED', dispute_reason = $2 WHERE id = $1", [input.performanceId, input.reason.trim()]);
    await createGameEvent(tx, { id: `CONTRACT-DISPUTE-${input.correlationId}`, category: 'INSTITUTION', eventType: 'ORGANIZATION_CONTRACT_DELIVERY_DISPUTED', gameDay: day, actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Contract delivery disputed', details: { performanceId: input.performanceId, contractId: row.contract_id, reason: input.reason.trim() }, correlationId: input.correlationId });
    return { ok: true, performanceId: input.performanceId, status: 'DISPUTED', correlationId: input.correlationId };
  });
}
