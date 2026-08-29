import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, moneyToCents, taxToCents } from './money';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';

export async function publicSpending(
  repository: PostgresRepository,
  input: { actorId: string; cityId: string; category: string; amount: number; correlationId: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const role = await tx.query("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = $1 AND role_assignments.institution_id = $2 AND role_assignments.status = 'active' AND institution_roles.name = ANY($3::text[]) AND role_assignments.ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [input.actorId, input.cityId, ['City Mayor', 'Infrastructure Planner']]);
    if (!role.rows[0]) throw new Error('An active City Mayor or Infrastructure Planner term is required');
    const prior = await tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'public_spending' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, correlationId: input.correlationId };
    const treasury = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE account_id = 'account-ouc-treasury'");
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!treasury.rows[0] || moneyToCents(treasury.rows[0].balance) < amountCents) throw new Error('OUC treasury cannot fund this spending');
    const city = await tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const cityAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE account_id = $1", [`account-city-${input.cityId}`]);
    if (!cityAccount.rows[0]) throw new Error('City credit account not found');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: treasury.rows[0].account_id, creditAccount: cityAccount.rows[0].account_id, amount, reasonType: 'public_spending', reasonId: input.cityId, ruleVersion: 'finance-v2', correlationId: input.correlationId });
    await tx.query('UPDATE cities SET treasury = treasury + $1 WHERE id = $2', [amount, input.cityId]);
    await tx.query('INSERT INTO budgets (id, institution_id, category, amount, game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET amount = budgets.amount + EXCLUDED.amount, game_day = EXCLUDED.game_day', [`SPEND-${input.cityId}-${input.category}`, input.cityId, input.category, amount, day]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'public_spending', `OUC funding reached ${input.cityId}`, toNanoMarkup({ cityId: input.cityId, category: input.category, amount, correlationId: input.correlationId, actorId: input.actorId })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.actorId, 'finance', 'Public spending recorded', `${amount} Credits were routed from the OUC treasury to ${input.cityId} for ${input.category}.`, input.correlationId]);
    const members = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 AND human_id <> $2', [input.cityId, input.actorId]);
    for (const member of members.rows) {
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), member.human_id, 'finance', 'City funding received', `${amount} Credits were routed to ${input.cityId} for ${input.category}.`, input.correlationId]);
    }
    return { ok: true, amount: Number(amount), cityId: input.cityId, category: input.category, gameDay: day, correlationId: input.correlationId };
  });
}

export async function settleTax(repository: PostgresRepository, humanId: string, taxableAmount: number): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [humanId]);
    const legacyRule = await tx.query<{ rate: string; version: number }>("SELECT rate, version FROM tax_rules WHERE id = 'TAX-OUC-BASIC' AND active = true");
    if (!account.rows[0] || !legacyRule.rows[0]) throw new Error('Tax rule or account not found');
    const rate = String(legacyRule.rows[0].rate);
    const version = Number(legacyRule.rows[0].version);
    const amountCents = taxToCents(taxableAmount, rate);
    const amount = centsToMoney(amountCents);
    const rateNumber = Number(rate);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const accountId = account.rows[0].account_id;
    const correlationId = `TAX-${accountId}-${gameDay}-${amount}-${version}`;
    const prior = await tx.query<{ id: string; amount: string; game_day: number; rule_version: string }>("SELECT id, amount, game_day, rule_version FROM ledger_entries WHERE reason_type = 'tax_settlement' AND correlation_id = $1", [correlationId]);
    if (prior.rows[0]) return { ok: true, alreadySettled: true, amount: Number(prior.rows[0].amount), gameDay: prior.rows[0].game_day, ruleVersion: prior.rows[0].rule_version, correlationId };
    if (amountCents === 0n) return { ok: true, alreadySettled: true, amount: 0, rate: rateNumber, ruleVersion: version, correlationId };
    const transfer = await transferCredits(tx, {
      ledgerId: crypto.randomUUID(),
      gameDay,
      debitAccount: accountId,
      creditAccount: 'account-ouc-treasury',
      amount,
      reasonType: 'tax_settlement',
      reasonId: accountId,
      ruleVersion: `tax-v${version}`,
      correlationId,
    });
    if (transfer.status === 'already_processed') return { ok: true, alreadySettled: true, amount: Number(transfer.amount), gameDay, ruleVersion: version, correlationId };
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING', [`TAX-SETTLED-${correlationId}`, humanId, 'finance', 'Tax settlement recorded', `${amount} Credits were settled to the OUC treasury at rate ${(rateNumber * 100).toFixed(2)}% (rule v${version}).`, correlationId]);
    return { ok: true, amount: Number(amount), rate: rateNumber, ruleVersion: version, correlationId };
  });
}

export async function declarePersonalInsolvency(repository: PostgresRepository, humanId: string, reason: string): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1 AND status = \'bankrupt\'', [humanId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, state: prior.rows[0] };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const buildings = await tx.query<{ id: string }>("SELECT id FROM buildings WHERE owner_id = $1 AND ownership_class = 'private' FOR UPDATE", [humanId]);
    const businesses = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE owner_id = $1 FOR UPDATE', [humanId]);
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [humanId]);
    if (!account.rows[0]) throw new Error('Human Credit account is required for insolvency');
    const currentCents = moneyToCents(account.rows[0].balance);
    const protectedTopUpCents = currentCents < 10000n ? 10000n - currentCents : 0n;
    const buildingValueCents = BigInt(buildings.rows.length) * 10000n;
    const treasuryAssetPaymentCents = buildingValueCents + BigInt(businesses.rows.length) * 10000n;
    const treasury = await tx.query<{ balance: string }>("SELECT balance FROM account_balances WHERE account_id = 'account-ouc-treasury'");
    if (!treasury.rows[0] || moneyToCents(treasury.rows[0].balance) < protectedTopUpCents + treasuryAssetPaymentCents) throw new Error('OUC treasury cannot fund insolvency protection and liquidation');
    if (protectedTopUpCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: 'account-ouc-treasury', creditAccount: account.rows[0].account_id, amount: centsToMoney(protectedTopUpCents), reasonType: 'insolvency_protection', reasonId: humanId, ruleVersion: 'finance-v3', correlationId: `INSOLVENCY-PROTECTION-${humanId}-${day}` });
    if (treasuryAssetPaymentCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: 'account-ouc-treasury', creditAccount: account.rows[0].account_id, amount: centsToMoney(treasuryAssetPaymentCents), reasonType: 'asset_liquidation', reasonId: humanId, ruleVersion: 'finance-v3', correlationId: `INSOLVENCY-ASSETS-${humanId}-${day}` });
    const liquidationValue = Number(centsToMoney(buildingValueCents + BigInt(businesses.rows.length) * 10000n));
    await tx.query("UPDATE buildings SET status = 'closed' WHERE owner_id = $1 AND ownership_class = 'private'", [humanId]);
    for (const business of businesses.rows) {
      await tx.query('DELETE FROM business_shares WHERE business_id = $1', [business.id]);
    }
    await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [humanId]);
    await tx.query('DELETE FROM businesses WHERE owner_id = $1', [humanId]);
    for (const business of businesses.rows) await tx.query("DELETE FROM institutions WHERE id = $1 AND kind = 'BUSINESS'", [business.id]);
    await tx.query('INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES ($1,\'bankrupt\',$2,100,$3) ON CONFLICT(human_id) DO UPDATE SET status = EXCLUDED.status, since_game_day = EXCLUDED.since_game_day, last_reason = EXCLUDED.last_reason, updated_at = CURRENT_TIMESTAMP', [humanId, day, reason]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [`PERSONAL-BANKRUPTCY-${humanId}-${day}`, day, 'human.bankruptcy', 'A Human entered insolvency restructuring', toNanoMarkup({ humanId, liquidationValue, protectedTopUp: Number(centsToMoney(protectedTopUpCents)), reason })]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), humanId, 'finance', 'Personal insolvency recorded', 'Non-protected private buildings and businesses were liquidated. The 100 Credit protected minimum remains.', `PERSONAL-BANKRUPTCY-${humanId}-${day}`]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [humanId]);
    return { ok: true, state: (await tx.query('SELECT * FROM personal_financial_states WHERE human_id = $1', [humanId])).rows[0], protectedCredits: 100, liquidated: { buildings: buildings.rows.length, businesses: businesses.rows.length, estimatedValue: liquidationValue } };
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
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [input.humanId]);
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < amountCents) throw new Error('Insufficient Credits for recovery');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 0);
    const table = institution.rows[0].kind === 'CITY' ? 'cities' : 'corporations';
    const institutionAccount = await tx.query<{ account_id: string }>('SELECT account_id FROM account_balances WHERE account_id = $1', [`account-${institution.rows[0].kind.toLowerCase()}-${input.institutionId}`]);
    if (!institutionAccount.rows[0]) throw new Error('Institution credit account not found');
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: account.rows[0].account_id, creditAccount: institutionAccount.rows[0].account_id, amount, reasonType: 'institution_recovery', reasonId: input.institutionId, ruleVersion: 'finance-v3', correlationId: input.correlationId });
    await tx.query(`UPDATE ${table} SET treasury = treasury + $1 WHERE id = $2`, [amount, input.institutionId]);
    await tx.query("UPDATE financial_states SET status = 'active', recovery_game_day = $1, last_reason = 'Player-authorized crisis recovery', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2", [gameDay, input.institutionId]);
    await tx.query('INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason) VALUES ($1,$2,$3,$4,\'active\',$5,$6)', [crypto.randomUUID(), input.institutionId, institution.rows[0].kind, state.rows[0].status, gameDay, 'Player-authorized crisis recovery']);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'financial_recovery', `${institution.rows[0].kind} ${input.institutionId} recovered`, toNanoMarkup({ institutionId: input.institutionId, amount: input.amount, humanId: input.humanId })]);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), input.humanId, 'finance', 'Institution recovered', `${institution.rows[0].kind} ${input.institutionId} returned to active status after your ${amount} Credit recovery contribution.`, input.institutionId]);
    return { ok: true, institutionId: input.institutionId, amount: Number(amount), status: 'active', correlationId: input.correlationId };
  });
}
