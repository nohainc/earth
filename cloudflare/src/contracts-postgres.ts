import type { PostgresRepository } from './repository.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { resolveOrganizationAuthority } from './organization-authority.ts';

async function day(tx: PostgresRepository): Promise<number> {
  return (await readAuthoritativeGameTime(tx)).gameDay;
}

export async function listOrganizationContracts(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const result = await repository.query(`SELECT c.id, c.template_id, c.buyer_organization_id, c.seller_organization_id, c.terms, c.status, c.start_game_day, c.end_game_day, c.amount_per_period::TEXT, c.period_days, COALESCE(jsonb_agg(jsonb_build_object('organizationId', s.organization_id, 'signedByHumanId', s.signed_by_human_id, 'signedGameDay', s.signed_game_day)) FILTER (WHERE s.organization_id IS NOT NULL), '[]'::jsonb) AS signatures FROM organization_contracts c LEFT JOIN organization_contract_signatures s ON s.contract_id = c.id WHERE c.buyer_organization_id = $1 OR c.seller_organization_id = $1 GROUP BY c.id ORDER BY c.status, c.end_game_day, c.id`, [organizationId]);
  return { organizationId, contracts: result.rows, generatedFrom: 'postgres-canonical-facts' };
}

function validateTerms(templateType: string, terms: Record<string, unknown>): void {
  const required: Record<string, string[]> = { RECURRING_SERVICE: ['serviceCode'], PROJECT_PROCUREMENT: ['deliverable'], LICENSE: ['patentId'], GUARANTEE: ['guaranteedAmount'] };
  if ((required[templateType] ?? []).some((key) => terms[key] === undefined || terms[key] === '')) throw new Error('Contract terms do not satisfy the approved template');
}

export async function createOrganizationContract(repository: PostgresRepository, input: { organizationId: string; counterpartyOrganizationId: string; templateId: string; terms: Record<string, unknown>; startGameDay: number; endGameDay: number; amountPerPeriod: string; periodDays: number; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM organization_contracts WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contractId: prior.rows[0].id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'ORGANIZATION_OPERATE' });
    if (input.organizationId === input.counterpartyOrganizationId) throw new Error('Contract parties must be different Organizations');
    const template = (await tx.query<{ contract_type: string }>('SELECT contract_type FROM contract_templates WHERE id = $1 AND status = \'ACTIVE\'', [input.templateId])).rows[0];
    if (!template) throw new Error('Approved contract template not found');
    validateTerms(template.contract_type, input.terms);
    const amount = BigInt(input.amountPerPeriod);
    if (amount <= 0n || input.startGameDay < 1 || input.endGameDay < input.startGameDay || input.periodDays < 1) throw new Error('Invalid contract schedule or amount');
    const id = `CONTRACT-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    await tx.query(`INSERT INTO organization_contracts (id, template_id, buyer_organization_id, seller_organization_id, terms, start_game_day, end_game_day, amount_per_period, period_days, created_by_human_id, correlation_id) VALUES ($1,$2,$3,$4,$5::JSONB,$6,$7,$8,$9,$10,$11)`, [id, input.templateId, input.organizationId, input.counterpartyOrganizationId, JSON.stringify(input.terms), input.startGameDay, input.endGameDay, amount.toString(), input.periodDays, input.humanId, input.correlationId]);
    await createGameEvent(tx, { id: `CONTRACT-CREATED-${id}`, category: 'INSTITUTION', eventType: 'ORGANIZATION_CONTRACT_CREATED', gameDay: await day(tx), actorHumanId: input.humanId, subjectType: 'ORGANIZATION', subjectId: input.organizationId, title: 'Organization contract created', details: { contractId: id, counterpartyOrganizationId: input.counterpartyOrganizationId, templateId: input.templateId }, correlationId: input.correlationId });
    return { ok: true, contractId: id, status: 'PENDING_SIGNATURE', correlationId: input.correlationId };
  });
}

export async function signOrganizationContract(repository: PostgresRepository, input: { organizationId: string; contractId: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ contract_id: string }>('SELECT contract_id FROM organization_contract_signatures WHERE correlation_id = $1', [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, contractId: prior.rows[0].contract_id, correlationId: input.correlationId };
    await resolveOrganizationAuthority(tx, { organizationId: input.organizationId, humanId: input.humanId, action: 'ORGANIZATION_OPERATE' });
    const contract = (await tx.query<{ buyer_organization_id: string; seller_organization_id: string; status: string; start_game_day: number; end_game_day: number; amount_per_period: string; period_days: number }>('SELECT buyer_organization_id, seller_organization_id, status, start_game_day, end_game_day, amount_per_period::TEXT, period_days FROM organization_contracts WHERE id = $1 FOR UPDATE', [input.contractId])).rows[0];
    if (!contract || contract.status !== 'PENDING_SIGNATURE' || ![contract.buyer_organization_id, contract.seller_organization_id].includes(input.organizationId)) throw new Error('Contract is not available for this Organization signature');
    const current = await day(tx);
    await tx.query(`INSERT INTO organization_contract_signatures (contract_id, organization_id, signed_by_human_id, signed_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5)`, [input.contractId, input.organizationId, input.humanId, current, input.correlationId]);
    const signatures = await tx.query<{ count: string }>('SELECT COUNT(*)::TEXT AS count FROM organization_contract_signatures WHERE contract_id = $1', [input.contractId]);
    let status = 'PENDING_SIGNATURE';
    if (Number(signatures.rows[0]?.count ?? 0) === 2) {
      status = 'ACTIVE';
      const obligationId = `OBL-CONTRACT-${input.contractId}-0`;
      await tx.query(`INSERT INTO financial_obligations (id, debtor_economic_id, creditor_economic_id, obligation_type, source_id, principal_due_units, debtor_account_purpose, creditor_account_purpose, due_game_day, priority_class, rule_version, created_game_day, correlation_id) SELECT $1, db.economic_id, cr.economic_id, 'SERVICE_INVOICE', $2, $3, 'TREASURY', 'TREASURY', $4, 60, 'contracts-v1', $5, $6 FROM owner_registry db JOIN owner_registry cr ON cr.id = $7 WHERE db.id = $8 ON CONFLICT (correlation_id) DO NOTHING`, [obligationId, input.contractId, contract.amount_per_period, Math.max(current, contract.start_game_day), current, `contract:${input.contractId}:period:0`, contract.seller_organization_id, contract.buyer_organization_id]);
      await tx.query(`INSERT INTO contract_performance_events (id, contract_id, period_start_game_day, period_end_game_day, status, obligation_id, correlation_id) VALUES ($1,$2,$3,$4,'DUE',$5,$6) ON CONFLICT (correlation_id) DO NOTHING`, [`PERF-${input.contractId}-0`, input.contractId, contract.start_game_day, Math.min(contract.end_game_day, contract.start_game_day + contract.period_days - 1), obligationId, `contract:${input.contractId}:performance:0`]);
      await tx.query('UPDATE organization_contracts SET status = $1 WHERE id = $2', [status, input.contractId]);
    }
    return { ok: true, contractId: input.contractId, organizationId: input.organizationId, status, correlationId: input.correlationId };
  });
}
