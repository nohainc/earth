import type { PostgresRepository } from './repository';

export async function createResearchProject(repository: PostgresRepository, input: { ownerId: string; name: string; budget: number; focus: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>("SELECT reason_id FROM ledger_entries WHERE reason_type = 'research_project_funding' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [prior.rows[0].reason_id])).rows[0], correlationId: input.correlationId };
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    if (!account.rows[0] || Number(account.rows[0].balance) < input.budget) throw new Error('Insufficient Credits for research funding');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const debited = await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [input.budget, account.rows[0].account_id]);
    if (debited.rowCount !== 1) throw new Error('Research funding reservation failed');
    const technologyId = `TECH-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const projectId = `PROJECT-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    await tx.query("INSERT INTO technologies (id, name, owner_id, progress, version, metadata) VALUES ($1,$2,$3,0,1,'{}')", [technologyId, input.name, input.ownerId]);
    await tx.query("INSERT INTO research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day, focus) VALUES ($1,$2,$3,$4,0,'active',$5,$6)", [projectId, technologyId, input.ownerId, input.budget, day, input.focus]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), day, account.rows[0].account_id, projectId, input.budget, 'CREDIT', 'research_project_funding', projectId, 'research-v1', input.correlationId]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Research project started', `${input.name} is now active with ${input.budget} Credits of funding.`, projectId]);
    return { ok: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [projectId])).rows[0], technology: (await tx.query('SELECT * FROM technologies WHERE id = $1', [technologyId])).rows[0], correlationId: input.correlationId };
  });
}

export async function fundResearchProject(repository: PostgresRepository, input: { ownerId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string; amount: string; game_day: number }>("SELECT reason_id, amount, game_day FROM ledger_entries WHERE reason_type = 'research_project_funding_increment' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [prior.rows[0].reason_id])).rows[0], correlationId: input.correlationId };
    const project = await tx.query<{ id: string; technology_id: string; owner_id: string; budget: string; progress: string }>('SELECT id, technology_id, owner_id, budget, progress FROM research_projects WHERE owner_id = $1 ORDER BY id LIMIT 1 FOR UPDATE', [input.ownerId]);
    if (!project.rows[0]) throw new Error('Research project not found');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    if (!account.rows[0] || Number(account.rows[0].balance) < input.amount) throw new Error('Insufficient Credits for research funding');
    const progress = Math.min(100, Number(project.rows[0].progress) + Math.min(10, input.amount / 60));
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const debited = await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [input.amount, account.rows[0].account_id]);
    if (debited.rowCount !== 1) throw new Error('Research funding reservation failed');
    await tx.query('UPDATE research_projects SET budget = budget + $1, progress = $2 WHERE id = $3', [input.amount, progress, project.rows[0].id]);
    await tx.query('UPDATE technologies SET progress = $1 WHERE id = $2', [progress, project.rows[0].technology_id]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), day, account.rows[0].account_id, project.rows[0].id, input.amount, 'CREDIT', 'research_project_funding_increment', project.rows[0].id, 'research-v2', input.correlationId]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.ownerId, 'technology', 'Research funding added', `${input.amount} Credits added to research project ${project.rows[0].id}.`, project.rows[0].id]);
    return { ok: true, project: (await tx.query('SELECT * FROM research_projects WHERE id = $1', [project.rows[0].id])).rows[0], technology: (await tx.query('SELECT * FROM technologies WHERE id = $1', [project.rows[0].technology_id])).rows[0], amount: input.amount, correlationId: input.correlationId };
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
    await tx.query('INSERT INTO patents (id, technology_id, owner_id, granted_game_day, expiry_game_day) VALUES ($1,$2,$3,$4,$5)', [patentId, project.rows[0].technology_id, input.ownerId, Number(world.rows[0]?.game_day ?? 0), Number(world.rows[0]?.game_day ?? 0) + 3650]);
    return { ok: true, patent: (await tx.query('SELECT * FROM patents WHERE id = $1', [patentId])).rows[0] };
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
    if (input.licenseeId !== input.ownerId) {
      const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id FOR UPDATE", [input.licenseeId, input.ownerId]);
      const buyer = accounts.rows.find((row) => row.owner_id === input.licenseeId);
      const owner = accounts.rows.find((row) => row.owner_id === input.ownerId);
      if (!buyer || !owner || Number(buyer.balance) < input.licenseFee) throw new Error('Licensee has insufficient Credits');
      const debited = await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [input.licenseFee, buyer.account_id]);
      if (debited.rowCount !== 1) throw new Error('License fee reservation failed');
      await tx.query('UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2', [input.licenseFee, owner.account_id]);
      await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), Number(world.rows[0]?.game_day ?? 0), buyer.account_id, owner.account_id, input.licenseFee, 'CREDIT', 'technology_license_fee', licenseId, 'technology-v3', input.correlationId]);
      await tx.query("UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = (SELECT id FROM businesses WHERE owner_id = $3 AND status = 'active' ORDER BY id LIMIT 1)", [input.licenseFee, Number(world.rows[0]?.game_day ?? 0), input.licenseeId]);
    }
    await tx.query("INSERT INTO technology_licenses (id, patent_id, licensor_id, licensee_id, royalty_rate) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET royalty_rate = excluded.royalty_rate, status = 'active'", [licenseId, patent.rows[0].id, input.ownerId, input.licenseeId, input.royaltyRate]);
    return { ok: true, license: (await tx.query('SELECT * FROM technology_licenses WHERE id = $1', [licenseId])).rows[0], licenseFee: input.licenseFee, correlationId: input.correlationId };
  });
}
