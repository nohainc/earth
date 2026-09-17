import type { PostgresRepository } from './repository.ts';
import { toJsonSafe } from './json-safe.ts';

// @mutation-boundary atomic-sql

async function activeCorporationMember(tx: PostgresRepository, humanId: string, corporationId: string) {
  const row = (await tx.query<{ house_id: string }>(`SELECT h.house_id FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.corporation_id = $2 AND ha.status = 'ACTIVE' WHERE h.id = $1 AND h.status = 'ACTIVE'`, [humanId, corporationId])).rows[0];
  if (!row) throw new Error('Active Corporation membership is required');
  return row;
}

export async function listV5CorporationReceivershipCases(repository: PostgresRepository, input: { humanId: string; corporationId: string }) {
  return repository.transaction(async (tx) => {
    await activeCorporationMember(tx, input.humanId, input.corporationId);
    const cases = await tx.query(`SELECT c.*, COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'planText', p.plan_text, 'proposedByHumanId', p.proposed_by_human_id, 'proposedGameDay', p.proposed_game_day, 'status', p.status) ORDER BY p.created_at DESC) FILTER (WHERE p.id IS NOT NULL), '[]'::JSONB) AS restructuring_plans
      FROM v5_corporation_receivership_cases c LEFT JOIN v5_corporation_restructuring_plans p ON p.case_id = c.id WHERE c.corporation_id = $1 GROUP BY c.id ORDER BY c.opened_game_day DESC, c.id DESC`, [input.corporationId]);
    return { ok: true, corporationId: input.corporationId, cases: toJsonSafe(cases.rows) };
  });
}

export async function submitV5CorporationRestructuringPlan(repository: PostgresRepository, input: { humanId: string; corporationId: string; caseId: string; planText: string; correlationId: string }) {
  return repository.transaction(async (tx) => {
    await activeCorporationMember(tx, input.humanId, input.corporationId);
    const role = (await tx.query(`SELECT 1 FROM institution_governance_roles WHERE institution_id = $1 AND human_id = $2 AND status = 'ACTIVE' AND role_code IN ('CORPORATION_EXECUTIVE','CORPORATION_TREASURER')`, [input.corporationId, input.humanId])).rows[0];
    if (!role) throw new Error('Corporation executive authorization is required');
    const text = input.planText.trim();
    if (text.length < 20 || text.length > 4000) throw new Error('Restructuring plan must be between 20 and 4000 characters');
    const existing = (await tx.query('SELECT * FROM v5_corporation_restructuring_plans WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (existing) return { ok: true, alreadyProcessed: true, plan: toJsonSafe(existing), correlationId: input.correlationId };
    const caseRow = (await tx.query<{ id: string; status: string }>(`SELECT id, status FROM v5_corporation_receivership_cases WHERE id = $1 AND corporation_id = $2 FOR UPDATE`, [input.caseId, input.corporationId])).rows[0];
    if (!caseRow || !['OPEN', 'RESTRUCTURING'].includes(caseRow.status)) throw new Error('Open Corporation receivership case not found');
    const day = Number((await tx.query<{ game_day: string }>("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);
    const id = `V5-RESTRUCTURE-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO v5_corporation_restructuring_plans (id, case_id, corporation_id, proposed_by_human_id, plan_text, proposed_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7)`, [id, input.caseId, input.corporationId, input.humanId, text, day, input.correlationId]);
    await tx.query("UPDATE v5_corporation_receivership_cases SET status = 'RESTRUCTURING' WHERE id = $1", [input.caseId]);
    return { ok: true, planId: id, caseId: input.caseId, corporationId: input.corporationId, status: 'SUBMITTED', proposedGameDay: day, correlationId: input.correlationId };
  });
}
