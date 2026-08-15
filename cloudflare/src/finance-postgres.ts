import type { PostgresRepository } from './repository';

export async function publicSpending(
  repository: PostgresRepository,
  input: { actorId: string; cityId: string; category: string; amount: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = await tx.query("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = $1 AND role_assignments.institution_id = $2 AND role_assignments.status = 'active' AND institution_roles.name = ANY($3::text[]) AND role_assignments.ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [input.actorId, input.cityId, ['City Mayor', 'Infrastructure Planner']]);
    if (!role.rows[0]) throw new Error('An active City Mayor or Infrastructure Planner term is required');
    const prior = await tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'public_spending' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, correlationId: input.correlationId };
    const treasury = await tx.query<{ balance: string }>("SELECT balance FROM account_balances WHERE account_id = 'account-ouc-treasury' FOR UPDATE");
    if (!treasury.rows[0] || Number(treasury.rows[0].balance) < input.amount) throw new Error('OUC treasury cannot fund this spending');
    const city = await tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query("UPDATE account_balances SET balance = balance - $1 WHERE account_id = 'account-ouc-treasury' AND balance >= $1", [input.amount]);
    await tx.query('UPDATE cities SET treasury = treasury + $1 WHERE id = $2', [input.amount, input.cityId]);
    await tx.query('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET amount = budgets.amount + EXCLUDED.amount, game_day = EXCLUDED.game_day', [`SPEND-${input.cityId}-${input.category}`, input.cityId, input.category, input.amount, day]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [input.correlationId, day, 'account-ouc-treasury', input.cityId, input.amount, 'CREDIT', 'public_spending', input.cityId, 'finance-v1', input.correlationId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'public_spending', `OUC funding reached ${input.cityId}`, JSON.stringify({ cityId: input.cityId, category: input.category, amount: input.amount, correlationId: input.correlationId, actorId: input.actorId })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.actorId, 'finance', 'Public spending recorded', `${input.amount} Credits were routed from the OUC treasury to ${input.cityId} for ${input.category}.`, input.correlationId]);
    const members = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 AND human_id <> $2', [input.cityId, input.actorId]);
    for (const member of members.rows) {
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), member.human_id, 'finance', 'City funding received', `${input.amount} Credits were routed to ${input.cityId} for ${input.category}.`, input.correlationId]);
    }
    return { ok: true, amount: input.amount, cityId: input.cityId, category: input.category, gameDay: day, correlationId: input.correlationId };
  });
}

export async function settleTax(repository: PostgresRepository, humanId: string, taxableAmount: number): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [humanId]);
    const legacyRule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true");
    if (!account.rows[0] || !legacyRule.rows[0]) throw new Error('Tax rule or account not found');
    const financeRule = await tx.query<{ value_json: unknown; version: number }>("SELECT value_json, version FROM governance_rules WHERE institution_id = 'OUC-001' AND category = 'finance' AND status = 'active' ORDER BY version DESC LIMIT 1");
    let rate = Number(legacyRule.rows[0].rate);
    let version = Number(legacyRule.rows[0].version);
    const configured = financeRule.rows[0]?.value_json;
    if (configured) {
      try {
        const value = typeof configured === 'string' ? JSON.parse(configured) : configured as { rate?: number };
        if (typeof value.rate === 'number' && value.rate >= 0 && value.rate <= 0.25) { rate = value.rate; version = Number(financeRule.rows[0].version); }
      } catch { /* retain the canonical tax rule */ }
    }
    const amount = Math.round(taxableAmount * rate * 100) / 100;
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const accountId = account.rows[0].account_id;
    const correlationId = `TAX-${accountId}-${gameDay}-${amount.toFixed(2)}-${version}`;
    const prior = await tx.query<{ id: string; amount: string; game_day: number; rule_version: string }>("SELECT id, amount, game_day, rule_version FROM ledger_entries WHERE reason_type = 'tax_settlement' AND correlation_id = $1", [correlationId]);
    if (prior.rows[0]) return { ok: true, alreadySettled: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, ruleVersion: prior.rows[0].rule_version, correlationId };
    if (Number(account.rows[0].balance) < amount) throw new Error('Insufficient Credits for tax settlement');
    await tx.query("UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1", [amount, accountId]);
    await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE account_id = 'account-ouc-treasury'", [amount]);
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [correlationId, gameDay, accountId, 'account-ouc-treasury', amount, 'CREDIT', 'tax_settlement', accountId, `tax-v${version}`, correlationId]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING', [`TAX-SETTLED-${correlationId}`, humanId, 'finance', 'Tax settlement recorded', `${amount} Credits were settled to the OUC treasury at rate ${(rate * 100).toFixed(2)}% (rule v${version}).`, correlationId]);
    return { ok: true, amount, rate, ruleVersion: version, correlationId };
  });
}

export async function declarePersonalInsolvency(repository: PostgresRepository, humanId: string, reason: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1 AND status = \'bankrupt\'', [humanId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, state: prior.rows[0] };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const machines = await tx.query<{ id: string; machine_type: string }>("SELECT id, machine_type FROM machines WHERE owner_id = $1 AND machine_type <> 'service-robot' FOR UPDATE", [humanId]);
    const businesses = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE owner_id = $1 FOR UPDATE', [humanId]);
    const liquidationValue = Math.round(machines.rows.length * 50 + businesses.rows.length * 100);
    await tx.query("UPDATE account_balances SET balance = GREATEST(100, balance) WHERE owner_id = $1 AND currency = 'CREDIT'", [humanId]);
    await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2 AND currency = 'CREDIT'", [liquidationValue, humanId]);
    await tx.query("DELETE FROM business_assets WHERE machine_id IN (SELECT id FROM machines WHERE owner_id = $1 AND machine_type <> 'service-robot')", [humanId]);
    await tx.query("DELETE FROM machines WHERE owner_id = $1 AND machine_type <> 'service-robot'", [humanId]);
    for (const business of businesses.rows) {
      await tx.query('DELETE FROM business_shares WHERE business_id = $1', [business.id]);
    }
    await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [humanId]);
    await tx.query('DELETE FROM businesses WHERE owner_id = $1', [humanId]);
    for (const business of businesses.rows) await tx.query("DELETE FROM institutions WHERE id = $1 AND kind = 'BUSINESS'", [business.id]);
    await tx.query('INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES ($1,\'bankrupt\',$2,100,$3) ON CONFLICT(human_id) DO UPDATE SET status = EXCLUDED.status, since_game_day = EXCLUDED.since_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP', [humanId, day, reason]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [`PERSONAL-BANKRUPTCY-${humanId}-${day}`, day, 'human.bankruptcy', 'A Human entered insolvency restructuring', JSON.stringify({ humanId, liquidationValue, reason })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), humanId, 'finance', 'Personal insolvency recorded', 'Non-protected productive assets were liquidated. Your basic service robot and 100 Credit protected minimum remain.', `PERSONAL-BANKRUPTCY-${humanId}-${day}`]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [humanId]);
    return { ok: true, state: (await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [humanId])).rows[0], protectedCredits: 100, liquidated: { machines: machines.rows.length, businesses: businesses.rows.length, estimatedValue: liquidationValue } };
  });
}

export async function recoverInstitution(repository: PostgresRepository, input: { humanId: string; institutionId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const institution = await tx.query<{ id: string; kind: 'CITY' | 'CORPORATION' }>("SELECT id, kind FROM institutions WHERE id = $1 AND kind IN ('CITY','CORPORATION') FOR UPDATE", [input.institutionId]);
    if (!institution.rows[0]) throw new Error('Recoverable institution not found');
    const roleNames = institution.rows[0].kind === 'CITY' ? ['City Mayor', 'Infrastructure Planner'] : ['Corporation Executive', 'Corporation Treasurer'];
    const role = await tx.query("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = $1 AND role_assignments.institution_id = $2 AND role_assignments.status = 'active' AND institution_roles.name = ANY($3::text[]) AND role_assignments.ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [input.humanId, input.institutionId, roleNames]);
    if (!role.rows[0]) throw new Error('An active institutional finance role is required');
    const state = await tx.query<{ status: string }>("SELECT status FROM financial_states WHERE institution_id = $1 AND status IN ('distressed','insolvent') FOR UPDATE", [input.institutionId]);
    if (!state.rows[0]) throw new Error('Institution is not currently in a recoverable crisis state');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.humanId]);
    if (!account.rows[0] || Number(account.rows[0].balance) < input.amount) throw new Error('Insufficient Credits for recovery');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const debit = await tx.query('UPDATE account_balances SET balance = balance - $1 WHERE account_id = $2 AND balance >= $1', [input.amount, account.rows[0].account_id]);
    if (debit.rowCount !== 1) throw new Error('Recovery payment reservation failed');
    const table = institution.rows[0].kind === 'CITY' ? 'cities' : 'corporations';
    await tx.query(`UPDATE ${table} SET treasury = treasury + $1 WHERE id = $2`, [input.amount, input.institutionId]);
    await tx.query("UPDATE financial_states SET status = 'active', recovery_game_day = $1, last_reason = 'Player-authorized crisis recovery', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2", [gameDay, input.institutionId]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,\'active\',$5,$6)', [crypto.randomUUID(), input.institutionId, institution.rows[0].kind, state.rows[0].status, gameDay, 'Player-authorized crisis recovery']);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'financial_recovery', `${institution.rows[0].kind} ${input.institutionId} recovered`, JSON.stringify({ institutionId: input.institutionId, amount: input.amount, humanId: input.humanId })]);
    await tx.query('INSERT INTO ledger_entries (id,game_day,debit_account,credit_account,amount,currency,reason_type,reason_id,rule_version,correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), gameDay, account.rows[0].account_id, input.institutionId, input.amount, 'CREDIT', 'institution_recovery', input.institutionId, 'finance-v2', input.correlationId]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.humanId, 'finance', 'Institution recovered', `${institution.rows[0].kind} ${input.institutionId} returned to active status after your ${input.amount} Credit recovery contribution.`, input.institutionId]);
    return { ok: true, institutionId: input.institutionId, amount: input.amount, status: 'active', correlationId: input.correlationId };
  });
}
