import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';

export const TECHNOLOGY_CATALOG = [
  'Automated Assembly',
  'Clean Energy Systems',
  'Food Synthesis',
  'Predictive Maintenance',
  'Civic Network Infrastructure',
] as const;

async function requireResearchJurisdiction(tx: PostgresRepository, ownerId: string): Promise<void> {
  const membership = await tx.query<{ city_id: string | null }>('SELECT city_id FROM memberships WHERE human_id = $1', [ownerId]);
  if (!membership.rows[0]?.city_id) {
    throw new Error('Research and machine upgrades require an active city affiliation');
  }
}

export async function createResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string; budget: number; focus: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    if (!(TECHNOLOGY_CATALOG as readonly string[]).includes(input.name)) {
      throw new Error('Technology must be selected from the approved research catalogue');
    }
    const prior = await tx.query<{ reason_id: string }>("SELECT reason_id FROM ledger_entries WHERE reason_type = 'research_project_funding' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [prior.rows[0].reason_id])).rows[0], correlationId: input.correlationId };
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [input.ownerId]);
    const budgetCents = moneyToCents(input.budget);
    const budget = centsToMoney(budgetCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < budgetCents) throw new Error('Insufficient Credits for research funding');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const technologyId = `TECH-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const projectId = `PROJECT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-research-registry', amount: budget, reasonType: 'research_project_funding', reasonId: projectId, ruleVersion: 'research-v3', correlationId: input.correlationId });
    await tx.query("INSERT INTO technologies (id, name, owner_id, progress, version) VALUES ($1,$2,$3,0,1)", [technologyId, input.name, input.ownerId]);
    await tx.query("INSERT INTO research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day, focus) VALUES ($1,$2,$3,$4,0,'active',$5,$6)", [projectId, technologyId, input.ownerId, budget, day, input.focus]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Research project started', `${input.name} is now active with ${input.budget} Credits of funding.`, projectId]);
    return { ok: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [projectId])).rows[0], technology: (await tx.query('SELECT * FROM technologies WHERE id = $1', [technologyId])).rows[0], correlationId: input.correlationId };
  });
}

export async function fundResearchProject(repository: PostgresRepository, input: { ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    const prior = await tx.query<{ reason_id: string; amount: string; game_day: number }>("SELECT reason_id, amount, game_day FROM ledger_entries WHERE reason_type = 'research_project_funding_increment' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [prior.rows[0].reason_id])).rows[0], correlationId: input.correlationId };
    const project = await tx.query<{ id: string; technology_id: string; owner_id: string; budget: string; progress: string }>('SELECT id, technology_id, owner_id, budget, progress FROM research_projects WHERE owner_id = $1 ORDER BY id LIMIT 1 FOR UPDATE', [input.ownerId]);
    if (!project.rows[0]) throw new Error('Research project not found');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [input.ownerId]);
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < amountCents) throw new Error('Insufficient Credits for research funding');
    const progress = Math.min(100, Number(project.rows[0].progress) + Math.min(10, input.amount / 60));
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-research-registry', amount, reasonType: 'research_project_funding_increment', reasonId: project.rows[0].id, ruleVersion: 'research-v3', correlationId: input.correlationId });
    await tx.query('UPDATE research_projects SET budget = budget + $1, progress = $2 WHERE id = $3', [amount, progress, project.rows[0].id]);
    await tx.query('UPDATE technologies SET progress = $1 WHERE id = $2', [progress, project.rows[0].technology_id]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Research funding added', `${input.amount} Credits added to research project ${project.rows[0].id}.`, project.rows[0].id]);
    return { ok: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [project.rows[0].id])).rows[0], technology: (await tx.query('SELECT * FROM technologies WHERE id = $1', [project.rows[0].technology_id])).rows[0], amount: Number(amount), correlationId: input.correlationId };
  });
}

export async function grantPatent(repository: PostgresRepository, input: { ownerId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const project = await tx.query<{ technology_id: string; progress: string; owner_id: string }>('SELECT technology_id, progress, owner_id FROM research_projects WHERE owner_id = $1 ORDER BY id LIMIT 1 FOR UPDATE', [input.ownerId]);
    if (!project.rows[0] || Number(project.rows[0].progress) < 100) throw new Error('Research must reach 100% before patent grant');
    const existing = await tx.query('SELECT * FROM patents WHERE technology_id = $1 AND status = \'active\'', [project.rows[0].technology_id]);
    if (existing.rows[0]) return { ok: true, alreadyProcessed: true, patent: existing.rows[0] };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const patentId = `PAT-${project.rows[0].technology_id}`;
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    await tx.query('INSERT INTO patents (id, technology_id, owner_id, granted_game_day, expiry_game_day) VALUES ($1,$2,$3,$4,$5)', [patentId, project.rows[0].technology_id, input.ownerId, gameDay, gameDay + 3650]);
    const affiliation = (await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.ownerId])).rows[0];
    let sharedCorporationId: string | null = null;
    if (affiliation?.corporation_id) {
      sharedCorporationId = affiliation.corporation_id;
      await tx.query('INSERT INTO corporation_technology_shares (id,corporation_id,patent_id,shared_by_human_id,shared_game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (corporation_id,patent_id) DO NOTHING', [crypto.randomUUID(), sharedCorporationId, patentId, input.ownerId, gameDay]);
    }
    return { ok: true, sharedCorporationId, patent: (await tx.query('SELECT * FROM patents WHERE id = $1', [patentId])).rows[0] };
  });
}

export async function licenseTechnology(repository: PostgresRepository, input: { ownerId: string; licenseeId: string; licenseeBusinessId?: string | null; royaltyRate: number; licenseFee: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ license_id: string; amount: string }>("SELECT reason_id AS license_id, amount FROM ledger_entries WHERE reason_type = 'technology_license_fee' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, license: (await tx.query('SELECT * FROM technology_licenses WHERE id = $1', [prior.rows[0].license_id])).rows[0], licenseFee: Number(prior.rows[0].amount), correlationId: input.correlationId };
    const patent = await tx.query<{ id: string; owner_id: string }>("SELECT id, owner_id FROM patents WHERE owner_id = $1 AND status = 'active' ORDER BY granted_game_day DESC LIMIT 1 FOR UPDATE", [input.ownerId]);
    if (!patent.rows[0]) throw new Error('An active patent is required');
    const licensee = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.licenseeId]);
    if (!licensee.rows[0]) throw new Error('Licensee not found');
    const licenseId = `LIC-${patent.rows[0].id}-${input.licenseeId}`;
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const sharedAccess = await tx.query<{ corporation_id: string }>("SELECT share.corporation_id FROM corporation_technology_shares share JOIN memberships owner_membership ON owner_membership.corporation_id = share.corporation_id AND owner_membership.human_id = $1 JOIN memberships licensee_membership ON licensee_membership.corporation_id = share.corporation_id AND licensee_membership.human_id = $2 WHERE share.patent_id = $3 AND share.status = 'active' LIMIT 1", [input.ownerId, input.licenseeId, patent.rows[0].id]);
    const internalShare = sharedAccess.rows.length > 0;
    if (input.licenseeId !== input.ownerId && !internalShare) {
      const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id", [input.licenseeId, input.ownerId]);
      const buyer = accounts.rows.find((row) => row.owner_id === input.licenseeId);
      const owner = accounts.rows.find((row) => row.owner_id === input.ownerId);
      const licenseFeeCents = moneyToCents(input.licenseFee);
      const licenseFee = centsToMoney(licenseFeeCents);
      if (!buyer || !owner || moneyToCents(buyer.balance) < licenseFeeCents) throw new Error('Licensee has insufficient Credits');
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: Number(world.rows[0]?.game_day ?? 0), debitAccount: buyer.account_id, creditAccount: owner.account_id, amount: licenseFee, reasonType: 'technology_license_fee', reasonId: licenseId, ruleVersion: 'technology-v4', correlationId: input.correlationId });
      const business = input.licenseeBusinessId
        ? await tx.query<{ id: string }>("SELECT b.id FROM businesses b LEFT JOIN business_management bm ON bm.business_id = b.id WHERE b.id = $1 AND b.status = 'active' AND (b.owner_id = $2 OR bm.manager_id = $2)", [input.licenseeBusinessId, input.licenseeId])
        : await tx.query<{ id: string }>("SELECT id FROM businesses WHERE owner_id = $1 AND status = 'active' ORDER BY id LIMIT 1", [input.licenseeId]);
      if (input.licenseeBusinessId && !business.rows[0]) throw new Error('License references a business the licensee cannot manage');
      if (business.rows[0]) {
        await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [licenseFee, Number(world.rows[0]?.game_day ?? 0), business.rows[0].id]);
      }
    }
    const effectiveFee = internalShare ? 0 : Number(centsToMoney(moneyToCents(input.licenseFee)));
    await tx.query("INSERT INTO technology_licenses (id, patent_id, licensor_id, licensee_id, royalty_rate) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET royalty_rate = excluded.royalty_rate, status = 'active'", [licenseId, patent.rows[0].id, input.ownerId, input.licenseeId, internalShare ? 0 : input.royaltyRate]);
    return { ok: true, internalShare, license: (await tx.query('SELECT * FROM technology_licenses WHERE id = $1', [licenseId])).rows[0], licenseFee: effectiveFee, correlationId: input.correlationId };
  });
}
