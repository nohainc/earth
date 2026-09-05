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

export const TECHNOLOGY_CATALOG_DETAILS = [
  { name: 'Automated Assembly', description: 'Improves building throughput for component and manufactured-goods production facilities.', researchCost: 240, subscriptionCost: 12, prerequisites: [], effect: 'assembly_output_bonus' },
  { name: 'Clean Energy Systems', description: 'Reduces the operating burden of energy-intensive workplaces and infrastructure.', researchCost: 320, subscriptionCost: 16, prerequisites: [], effect: 'energy_efficiency' },
  { name: 'Food Synthesis', description: 'Enables high-yield food production for resilient local supply.', researchCost: 280, subscriptionCost: 14, prerequisites: [], effect: 'food_output_bonus' },
  { name: 'Predictive Maintenance', description: 'Reduces building upkeep costs when actively adopted by a business.', researchCost: 300, subscriptionCost: 15, prerequisites: [], effect: 'maintenance_reduction' },
  { name: 'Civic Network Infrastructure', description: 'Improves the coordination capacity of city services and civic institutions.', researchCost: 360, subscriptionCost: 18, prerequisites: [], effect: 'civic_capacity_bonus' },
].map((technology) => ({
  ...technology,
  kind: 'approved_capability',
  tradeable: false,
  playerCreated: false,
}));

export async function adoptTechnology(repository: PostgresRepository, input: { humanId: string; technologyId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.humanId);
    const technology = await tx.query<{ id: string; name: string; progress: string; owner_id: string }>('SELECT id, name, progress, owner_id FROM technologies WHERE id = $1 AND progress >= 100', [input.technologyId]);
    if (!technology.rows[0]) throw new Error('Technology must be fully researched before adoption');
    if (!(TECHNOLOGY_CATALOG as readonly string[]).includes(technology.rows[0].name)) throw new Error('Technology is outside the approved research catalogue');
    if (technology.rows[0].owner_id !== input.humanId) {
      const access = await tx.query<{ source: string }>(`SELECT 'license' AS source
        FROM technology_licenses
        JOIN patents ON patents.id = technology_licenses.patent_id
        WHERE patents.technology_id = $1 AND technology_licenses.licensee_id = $2 AND technology_licenses.status = 'active'
        UNION ALL
        SELECT 'corporation_share' AS source
        FROM patents
        JOIN corporation_technology_shares shares ON shares.patent_id = patents.id AND shares.status = 'active'
        JOIN memberships member ON member.corporation_id = shares.corporation_id AND member.human_id = $2
        WHERE patents.technology_id = $1
        LIMIT 1`, [input.technologyId, input.humanId]);
      if (!access.rows[0]) throw new Error('Technology requires ownership, an active license, or corporation sharing');
    }
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query("INSERT INTO human_technology_adoptions (human_id, technology_id, adopted_game_day, status) VALUES ($1,$2,$3,'active') ON CONFLICT (human_id, technology_id) DO UPDATE SET adopted_game_day = excluded.adopted_game_day, status = 'active'", [input.humanId, input.technologyId, day]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,\'technology.adopted\',$3,$4)', [crypto.randomUUID(), day, `${technology.rows[0].name} adopted by Human`, JSON.stringify({ humanId: input.humanId, technologyId: input.technologyId })]);
    return { ok: true, humanId: input.humanId, technologyId: input.technologyId, technologyName: technology.rows[0].name, adoptedGameDay: day };
  });
}

async function requireResearchJurisdiction(tx: PostgresRepository, ownerId: string): Promise<void> {
  const membership = await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [ownerId]);
  if (!membership.rows[0]?.corporation_id) throw new Error('Research requires active corporation membership');
}

export async function createResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string; budget: number; focus: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    if (!(TECHNOLOGY_CATALOG as readonly string[]).includes(input.name)) {
      throw new Error('Technology must be selected from the approved research catalogue');
    }
    const catalogEntry = TECHNOLOGY_CATALOG_DETAILS.find((technology) => technology.name === input.name);
    if (!catalogEntry || input.budget < catalogEntry.researchCost) {
      throw new Error(`Research funding for ${input.name} must be at least ${catalogEntry?.researchCost ?? 240} Credits`);
    }
    const membership = await tx.query<{ corporation_id: string }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.ownerId]);
    const corporationId = membership.rows[0].corporation_id;
    const prior = await tx.query<{ id: string }>('SELECT id FROM corporation_technology_projects WHERE corporation_id = $1 AND correlation_id = $2', [corporationId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, project: (await tx.query('SELECT * FROM corporation_technology_projects WHERE id = $1', [prior.rows[0].id])).rows[0], correlationId: input.correlationId };
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [corporationId]);
    const budgetCents = moneyToCents(input.budget);
    const budget = centsToMoney(budgetCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < budgetCents) throw new Error('Insufficient Credits for research funding');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const projectId = `PROJECT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-research-registry', amount: budget, reasonType: 'corporation_technology_research', reasonId: projectId, ruleVersion: 'corporation-technology-v1', correlationId: input.correlationId });
    await tx.query(`INSERT INTO corporation_technology_projects (id, corporation_id, technology_key, technology_name, research_cost_credits, subscription_cost_credits, effect_key, progress, status, started_game_day, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,0,'active',$8,$9)`, [projectId, corporationId, input.name.toLowerCase().replaceAll(' ', '_'), input.name, budget, catalogEntry.subscriptionCost, catalogEntry.effect, day, input.correlationId]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Corporation research started', `${input.name} is now being researched by your corporation.`, projectId]);
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_technology_projects WHERE id = $1', [projectId])).rows[0], correlationId: input.correlationId };
  });
}

export async function fundResearchProject(repository: PostgresRepository, input: { ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
    const membership = await tx.query<{ corporation_id: string }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.ownerId]);
    const corporationId = membership.rows[0]?.corporation_id;
    if (!corporationId) throw new Error('Research requires active corporation membership');
    const prior = await tx.query<{ reason_id: string; amount: string; game_day: number }>("SELECT reason_id, amount, game_day FROM ledger_entries WHERE reason_type = 'corporation_technology_research' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, project: (await tx.query('SELECT * FROM corporation_technology_projects WHERE id = $1', [prior.rows[0].reason_id])).rows[0], correlationId: input.correlationId };
    const project = await tx.query<{ id: string; research_cost_credits: string; progress: string; status: string }>('SELECT id, research_cost_credits, progress, status FROM corporation_technology_projects WHERE corporation_id = $1 AND status = \'active\' ORDER BY created_at LIMIT 1 FOR UPDATE', [corporationId]);
    if (!project.rows[0]) throw new Error('Research project not found');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [corporationId]);
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < amountCents) throw new Error('Insufficient Credits for research funding');
    const progress = Math.min(100, Number(project.rows[0].progress) + (amount / Number(project.rows[0].research_cost_credits)) * 100);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-research-registry', amount, reasonType: 'corporation_technology_research', reasonId: project.rows[0].id, ruleVersion: 'corporation-technology-v1', correlationId: input.correlationId });
    await tx.query("UPDATE corporation_technology_projects SET progress = $1, status = CASE WHEN $1 >= 100 THEN 'completed' ELSE status END, completed_game_day = CASE WHEN $1 >= 100 THEN $2 ELSE completed_game_day END, updated_at = CURRENT_TIMESTAMP WHERE id = $3", [progress, day, project.rows[0].id]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Research funding added', `${input.amount} Credits added to research project ${project.rows[0].id}.`, project.rows[0].id]);
    return { ok: true, project: (await tx.query('SELECT * FROM corporation_technology_projects WHERE id = $1', [project.rows[0].id])).rows[0], amount: Number(amount), correlationId: input.correlationId };
  });
}

export async function setHumanTechnologySubscription(repository: PostgresRepository, input: { humanId: string; technologyKey: string; status: 'active' | 'inactive'; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const membership = await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.humanId]);
    const corporationId = membership.rows[0]?.corporation_id;
    if (!corporationId) throw new Error('Technology subscriptions require active corporation membership');
    const project = await tx.query<{ technology_name: string; subscription_cost_credits: string }>(`SELECT technology_name, subscription_cost_credits
      FROM corporation_technology_projects WHERE corporation_id = $1 AND technology_key = $2 AND status = 'completed'`, [corporationId, input.technologyKey]);
    if (!project.rows[0]) throw new Error('Technology must be fully researched by the corporation before subscription');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query(`INSERT INTO human_technology_subscriptions (human_id, corporation_id, technology_key, subscription_cost_credits, status, subscribed_game_day, unsubscribed_game_day, updated_at)
      VALUES ($1,$2,$3,$4,$5,CASE WHEN $5 = 'active' THEN $6 ELSE NULL END,CASE WHEN $5 = 'inactive' THEN $6 ELSE NULL END,CURRENT_TIMESTAMP)
      ON CONFLICT (human_id, technology_key) DO UPDATE SET status = excluded.status, subscription_cost_credits = excluded.subscription_cost_credits,
      subscribed_game_day = CASE WHEN excluded.status = 'active' THEN excluded.subscribed_game_day ELSE human_technology_subscriptions.subscribed_game_day END,
      unsubscribed_game_day = CASE WHEN excluded.status = 'inactive' THEN excluded.unsubscribed_game_day ELSE human_technology_subscriptions.unsubscribed_game_day END,
      updated_at = CURRENT_TIMESTAMP`, [input.humanId, corporationId, input.technologyKey, Number(project.rows[0].subscription_cost_credits), input.status, day]);
    return { ok: true, humanId: input.humanId, technologyKey: input.technologyKey, technologyName: project.rows[0].technology_name, status: input.status, subscriptionCostCredits: Number(project.rows[0].subscription_cost_credits), gameDay: day, correlationId: input.correlationId };
  });
}

export async function grantPatent(repository: PostgresRepository, input: { ownerId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await requireResearchJurisdiction(tx, input.ownerId);
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

export async function licenseTechnology(repository: PostgresRepository, input: { ownerId: string; licenseeId: string; royaltyRate: number; licenseFee: number; correlationId: string }): Promise<Record<string, unknown>> {
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
    }
    const effectiveFee = internalShare ? 0 : Number(centsToMoney(moneyToCents(input.licenseFee)));
      await tx.query("INSERT INTO technology_licenses (id, patent_id, licensor_id, licensee_id, royalty_rate) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET royalty_rate = excluded.royalty_rate, status = 'active'", [licenseId, patent.rows[0].id, input.ownerId, input.licenseeId, internalShare ? 0 : input.royaltyRate]);
    return { ok: true, internalShare, license: (await tx.query('SELECT * FROM technology_licenses WHERE id = $1', [licenseId])).rows[0], licenseFee: effectiveFee, correlationId: input.correlationId };
  });
}
