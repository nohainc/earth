import type { PostgresRepository } from './repository.ts';
import { evaluateOrganizationHealth } from './organization-stress.ts';
import { createGameEvent } from './game-events-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

export async function refreshOrganizationFinancialStates(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const organizations = await tx.query<{ id: string; economic_id: string }>("SELECT o.id, e.economic_id FROM organizations o JOIN organization_economies e ON e.organization_id = o.id WHERE o.status <> 'DISSOLVED' ORDER BY o.id LIMIT 100");
  let evaluated = 0;
  let insolvent = 0;
  for (const organization of organizations.rows) {
    const accounts = await tx.query<{ assets: string; liquid: string }>("SELECT COALESCE(SUM(balance_units),0)::TEXT AS assets, COALESCE(SUM(balance_units) FILTER (WHERE account_type IN ('TREASURY','OPERATIONS','RESERVE')),0)::TEXT AS liquid FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND status = 'ACTIVE'", [organization.economic_id]);
    const obligations = await tx.query<{ liabilities: string; overdue: string }>("SELECT COALESCE(SUM(principal_due_units + interest_due_units - paid_units),0)::TEXT AS liabilities, COALESCE(SUM(principal_due_units + interest_due_units - paid_units) FILTER (WHERE due_game_day < $2 AND status IN ('DUE','PARTIAL','ARREARS')),0)::TEXT AS overdue FROM financial_obligations WHERE debtor_economic_id = $1 AND status IN ('DUE','PARTIAL','ARREARS')", [organization.economic_id, gameDay]);
    const assets = BigInt(accounts.rows[0]?.assets ?? 0);
    const liquid = BigInt(accounts.rows[0]?.liquid ?? 0);
    const liabilities = BigInt(obligations.rows[0]?.liabilities ?? 0);
    const overdue = BigInt(obligations.rows[0]?.overdue ?? 0);
    const status = evaluateOrganizationHealth({ assetsUnits: assets, liquidUnits: liquid, liabilitiesUnits: liabilities, overdueUnits: overdue });
    const previous = (await tx.query<{ status: string; since_game_day: number }>('SELECT status, since_game_day FROM organization_financial_states WHERE organization_id = $1', [organization.id])).rows[0];
    await tx.query(`INSERT INTO organization_financial_states (organization_id,status,assets_units,liabilities_units,liquid_units,overdue_units,since_game_day,evaluated_game_day,rules_version) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'organization-risk-v1') ON CONFLICT (organization_id) DO UPDATE SET status = EXCLUDED.status, assets_units = EXCLUDED.assets_units, liabilities_units = EXCLUDED.liabilities_units, liquid_units = EXCLUDED.liquid_units, overdue_units = EXCLUDED.overdue_units, since_game_day = EXCLUDED.since_game_day, evaluated_game_day = EXCLUDED.evaluated_game_day, rules_version = EXCLUDED.rules_version`, [organization.id, status, assets.toString(), liabilities.toString(), liquid.toString(), overdue.toString(), previous?.status === status ? previous.since_game_day : gameDay, gameDay]);
    await tx.query(`INSERT INTO organization_financial_state_history (id,organization_id,status,assets_units,liabilities_units,liquid_units,overdue_units,game_day,rules_version,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'organization-risk-v1',$9) ON CONFLICT (correlation_id) DO NOTHING`, [`ORG-RISK-${organization.id}-${gameDay}`, organization.id, status, assets.toString(), liabilities.toString(), liquid.toString(), overdue.toString(), gameDay, `org-risk:${organization.id}:${gameDay}`]);
    if (status === 'INSOLVENT') {
      await tx.query(`INSERT INTO organization_resolution_cases (id, organization_id, case_type, opened_game_day, correlation_id, details) SELECT $1,$2,'RESTRUCTURE',$3,$4,$5::JSONB WHERE NOT EXISTS (SELECT 1 FROM organization_resolution_cases WHERE organization_id = $2 AND status IN ('OPEN','APPROVED','EXECUTING'))`, [`RESOLUTION-${organization.id}-${gameDay}`, organization.id, gameDay, `resolution:${organization.id}:${gameDay}`, JSON.stringify({ trigger: 'INSOLVENT', rulesVersion: 'organization-risk-v1' })]);
      insolvent += 1;
    }
    evaluated += 1;
  }
  return { ok: true, gameDay, evaluated, insolvent };
}

export async function getOrganizationFinancialState(repository: PostgresRepository, organizationId: string): Promise<Record<string, unknown>> {
  const state = (await repository.query('SELECT * FROM organization_financial_states WHERE organization_id = $1', [organizationId])).rows[0];
  const cases = await repository.query('SELECT id, case_type, status, opened_game_day, effective_game_day, details FROM organization_resolution_cases WHERE organization_id = $1 ORDER BY opened_game_day DESC, id DESC', [organizationId]);
  const claims = await repository.query('SELECT id, creditor_economic_id, source_type, source_id, claim_units::TEXT, priority_rank, status, created_game_day FROM organization_creditor_claims WHERE organization_id = $1 ORDER BY priority_rank, created_game_day, id', [organizationId]);
  return { organizationId, state: state ?? null, cases: cases.rows, claims: claims.rows, generatedFrom: 'postgres-canonical-facts' };
}

export async function openOrganizationResolutionCase(repository: PostgresRepository, input: { organizationId: string; proposalId: string; caseType: 'DISSOLUTION' | 'MERGER' | 'SPLIT' | 'RESTRUCTURE'; successorOrganizationId?: string; humanId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = (await tx.query<{ id: string }>('SELECT id FROM organization_resolution_cases WHERE correlation_id = $1', [input.correlationId])).rows[0];
    if (prior) return { ok: true, alreadyProcessed: true, caseId: prior.id, correlationId: input.correlationId };
    const proposal = (await tx.query<{ subject_type: string; subject_id: string | null; status: string }>('SELECT subject_type, subject_id, status FROM governance_proposals_v4 WHERE id = $1', [input.proposalId])).rows[0];
    if (!proposal || proposal.subject_type !== 'ORGANIZATION' || proposal.subject_id !== input.organizationId || proposal.status !== 'PASSED') throw new Error('Resolution requires a passed proposal for this Organization');
    const organization = (await tx.query<{ id: string }>("SELECT id FROM organizations WHERE id = $1 AND status <> 'DISSOLVED' FOR UPDATE", [input.organizationId])).rows[0];
    if (!organization) throw new Error('Organization is unavailable for resolution');
    if (input.caseType !== 'DISSOLUTION' && !input.successorOrganizationId) throw new Error('Merger, split, and restructure cases require a successor Organization');
    if (input.successorOrganizationId) {
      const successor = (await tx.query<{ id: string }>("SELECT id FROM organizations WHERE id = $1 AND status = 'ACTIVE'", [input.successorOrganizationId])).rows[0];
      if (!successor || successor.id === input.organizationId) throw new Error('Successor Organization is unavailable');
    }
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    const caseId = `RESOLUTION-${crypto.randomUUID().slice(0, 12).toUpperCase()}`;
    const effectiveDay = day + 1;
    await tx.query(`INSERT INTO organization_resolution_cases (id, organization_id, case_type, status, opened_game_day, effective_game_day, approved_proposal_id, correlation_id, details) VALUES ($1,$2,$3,'APPROVED',$4,$5,$6,$7,$8::JSONB)`, [caseId, input.organizationId, input.caseType, day, effectiveDay, input.proposalId, input.correlationId, JSON.stringify({ successorOrganizationId: input.successorOrganizationId ?? null, approvedByHumanId: input.humanId, rulesVersion: 'organization-resolution-v1' })]);
    if (input.successorOrganizationId) await tx.query(`INSERT INTO organization_successor_mappings (id, resolution_case_id, predecessor_organization_id, successor_organization_id, effective_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)`, [`SUCCESSOR-${caseId}`, caseId, input.organizationId, input.successorOrganizationId, effectiveDay, `${input.correlationId}:successor`]);
    return { ok: true, caseId, organizationId: input.organizationId, caseType: input.caseType, successorOrganizationId: input.successorOrganizationId ?? null, effectiveGameDay: effectiveDay, correlationId: input.correlationId };
  });
}

async function executeOrganizationResolutionInTransaction(tx: PostgresRepository, caseId: string, gameDay: number): Promise<Record<string, unknown>> {
  const resolution = (await tx.query<any>("SELECT * FROM organization_resolution_cases WHERE id = $1 AND status = 'APPROVED' AND effective_game_day <= $2 FOR UPDATE", [caseId, gameDay])).rows[0];
  if (!resolution) return { ok: true, alreadyProcessed: true, caseId };
  const successorId = (await tx.query<{ successor_organization_id: string }>('SELECT successor_organization_id FROM organization_successor_mappings WHERE resolution_case_id = $1 FOR UPDATE', [caseId])).rows[0]?.successor_organization_id ?? null;
  const predecessor = (await tx.query<{ economic_id: string }>('SELECT e.economic_id FROM organizations o JOIN organization_economies e ON e.organization_id = o.id WHERE o.id = $1 FOR UPDATE', [resolution.organization_id])).rows[0];
  if (!predecessor) throw new Error('Resolution predecessor economy is unavailable');
  if (!successorId) {
    const activeAssets = (await tx.query<{ count: string }>("SELECT COUNT(*)::TEXT AS count FROM buildings WHERE owner_economic_id = $1 AND status = 'ACTIVE'", [predecessor.economic_id])).rows[0];
    if (Number(activeAssets?.count ?? 0) > 0) {
      await tx.query("UPDATE organization_resolution_cases SET status = 'CANCELLED', details = details || $1::JSONB WHERE id = $2", [JSON.stringify({ blockedReason: 'active assets have no successor' }), caseId]);
      return { ok: false, caseId, status: 'CANCELLED', reason: 'active assets have no successor' };
    }
    await tx.query("UPDATE organizations SET status = 'DISSOLVED' WHERE id = $1", [resolution.organization_id]);
    await tx.query("UPDATE organization_resolution_cases SET status = 'COMPLETED' WHERE id = $1", [caseId]);
    await createGameEvent(tx, { id: `ORG-RESOLUTION-${caseId}`, category: 'GOVERNANCE', eventType: 'ORGANIZATION_DISSOLVED', gameDay, actorHumanId: null, subjectType: 'ORGANIZATION', subjectId: resolution.organization_id, title: 'Organization dissolved', details: { caseId, caseType: resolution.case_type }, correlationId: `org-resolution:${caseId}` });
    return { ok: true, caseId, status: 'COMPLETED', organizationId: resolution.organization_id };
  }
  const successor = (await tx.query<{ economic_id: string }>('SELECT e.economic_id FROM organizations o JOIN organization_economies e ON e.organization_id = o.id WHERE o.id = $1 AND o.status = \'ACTIVE\' FOR UPDATE', [successorId])).rows[0];
  if (!successor) throw new Error('Resolution successor economy is unavailable');
  const buildings = await tx.query<{ id: string }>("SELECT id FROM buildings WHERE owner_economic_id = $1 AND status = 'ACTIVE' FOR UPDATE", [predecessor.economic_id]);
  for (const building of buildings.rows) await tx.query('UPDATE buildings SET owner_economic_id = $1 WHERE id = $2', [successor.economic_id, building.id]);
  await tx.query('UPDATE organization_contracts SET buyer_organization_id = $1 WHERE buyer_organization_id = $2', [successorId, resolution.organization_id]);
  await tx.query('UPDATE organization_contracts SET seller_organization_id = $1 WHERE seller_organization_id = $2', [successorId, resolution.organization_id]);
  const positions = await tx.query<any>("SELECT * FROM asset_ownership_positions WHERE holder_type = 'ORGANIZATION' AND holder_id = $1 AND status = 'ACTIVE' AND effective_to_game_day IS NULL FOR UPDATE", [resolution.organization_id]);
  let transferredUnits = 0n;
  for (const position of positions.rows) {
    const destination = (await tx.query<any>("SELECT * FROM asset_ownership_positions WHERE asset_type = $1 AND asset_id = $2 AND holder_type = 'ORGANIZATION' AND holder_id = $3 AND ownership_class = $4 AND status = 'ACTIVE' AND effective_to_game_day IS NULL FOR UPDATE", [position.asset_type, position.asset_id, successorId, position.ownership_class])).rows[0];
    if (destination) {
      await tx.query('UPDATE asset_ownership_positions SET units = units + $1 WHERE id = $2', [position.units, destination.id]);
      await tx.query("UPDATE asset_ownership_positions SET status = 'SUPERSEDED', effective_to_game_day = $1 WHERE id = $2", [gameDay, position.id]);
    } else await tx.query('UPDATE asset_ownership_positions SET holder_id = $1 WHERE id = $2', [successorId, position.id]);
    transferredUnits += BigInt(position.units);
  }
  const memberships = await tx.query<{ house_id: string; role_code: string }>("SELECT house_id, role_code FROM organization_memberships WHERE organization_id = $1 AND status = 'ACTIVE' FOR UPDATE", [resolution.organization_id]);
  for (const membership of memberships.rows) {
    await tx.query(`INSERT INTO organization_memberships (organization_id, house_id, role_code, status, joined_game_day, correlation_id) VALUES ($1,$2,$3,'ACTIVE',$4,$5) ON CONFLICT (organization_id, house_id) WHERE status = 'ACTIVE' DO NOTHING`, [successorId, membership.house_id, membership.role_code, gameDay, `resolution:${caseId}:membership:${membership.house_id}`]);
    await tx.query("UPDATE organization_memberships SET status = 'LEFT', left_game_day = $1 WHERE organization_id = $2 AND house_id = $3 AND status = 'ACTIVE'", [gameDay, resolution.organization_id, membership.house_id]);
  }
  await tx.query("UPDATE organization_successor_mappings SET transferred_asset_units = $1 WHERE resolution_case_id = $2", [transferredUnits.toString(), caseId]);
  if (resolution.case_type === 'MERGER' || resolution.case_type === 'DISSOLUTION') await tx.query("UPDATE organizations SET status = 'DISSOLVED' WHERE id = $1", [resolution.organization_id]);
  await tx.query("UPDATE organization_resolution_cases SET status = 'COMPLETED' WHERE id = $1", [caseId]);
  await createGameEvent(tx, { id: `ORG-RESOLUTION-${caseId}`, category: 'GOVERNANCE', eventType: 'ORGANIZATION_RESOLUTION_COMPLETED', gameDay, actorHumanId: null, subjectType: 'ORGANIZATION', subjectId: resolution.organization_id, title: 'Organization resolution completed', details: { caseId, caseType: resolution.case_type, successorOrganizationId: successorId, transferredAssetUnits: transferredUnits.toString() }, correlationId: `org-resolution:${caseId}` });
  return { ok: true, caseId, status: 'COMPLETED', predecessorOrganizationId: resolution.organization_id, successorOrganizationId: successorId, transferredAssetUnits: transferredUnits.toString(), transferredMemberships: memberships.rows.length };
}

export async function executeDueOrganizationResolutions(tx: PostgresRepository, gameDay: number): Promise<Record<string, unknown>> {
  const cases = await tx.query<{ id: string }>("SELECT id FROM organization_resolution_cases WHERE status = 'APPROVED' AND effective_game_day <= $1 ORDER BY effective_game_day, id LIMIT 100 FOR UPDATE SKIP LOCKED", [gameDay]);
  let completed = 0;
  for (const resolution of cases.rows) { await executeOrganizationResolutionInTransaction(tx, resolution.id, gameDay); completed += 1; }
  return { ok: true, gameDay, completed };
}
