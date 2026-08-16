import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, marketValueToCents, moneyToCents } from './money';

const sectors = new Set(['energy', 'extraction', 'components', 'machines', 'maintenance', 'housing', 'compute', 'r-and-d']);

export async function createBusiness(repository: PostgresRepository, input: { ownerId: string; name: string; sector: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>("SELECT reason_id FROM ledger_entries WHERE reason_type = 'business_registration' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, business: (await tx.query('SELECT * FROM businesses WHERE id = $1', [prior.rows[0].reason_id])).rows[0], shares: 100, correlationId: input.correlationId };
    if (!sectors.has(input.sector)) throw new Error('Business sector is invalid');
    const nameConflict = await tx.query('SELECT id FROM institutions WHERE name = $1', [input.name]);
    if (nameConflict.rows[0]) throw new Error('Business name already exists');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    const feeCents = 25000n;
    const fee = centsToMoney(feeCents);
    if (!account.rows[0] || moneyToCents(account.rows[0].balance) < feeCents) throw new Error('Business registration requires 250 Credits');
    const businessId = `B-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: account.rows[0].account_id, creditAccount: 'account-ouc-treasury', amount: fee, reasonType: 'business_registration', reasonId: businessId, ruleVersion: 'business-v2', correlationId: input.correlationId });
    await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'BUSINESS', $2, 'active')", [businessId, input.name]);
    await tx.query("INSERT INTO businesses (id, owner_id, name, policy, condition, sector) VALUES ($1,$2,$3,'reliability',100,$4)", [businessId, input.ownerId, input.name, input.sector]);
    await tx.query('INSERT INTO business_financials (business_id, last_game_day) VALUES ($1,$2)', [businessId, day]);
    await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,100)', [businessId, input.ownerId]);
    await tx.query('INSERT INTO business_constitutions (business_id, updated_by, updated_game_day) VALUES ($1,$2,$3)', [businessId, input.ownerId, day]);
    await tx.query('INSERT INTO business_management (business_id, manager_id, appointed_by, appointed_game_day) VALUES ($1,$2,$2,$3)', [businessId, input.ownerId, day]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.formed', `${input.name} was registered`, JSON.stringify({ businessId, sector: input.sector, founder: input.ownerId })]);
    return { ok: true, business: (await tx.query('SELECT * FROM businesses WHERE id = $1', [businessId])).rows[0], shares: 100, fee: Number(fee), correlationId: input.correlationId };
  });
}

export async function transferShares(repository: PostgresRepository, input: { holderId: string; businessId: string | null; recipientId: string; shares: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ business_id: string; quantity: string }>("SELECT asset_id AS business_id, quantity FROM ownership_events WHERE reason_type = 'share_transfer' AND reason_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, businessId: prior.rows[0].business_id, shares: Number(prior.rows[0].quantity), correlationId: input.correlationId };
    const business = await tx.query<{ id: string }>(input.businessId ? 'SELECT id FROM businesses WHERE id = $1 FOR UPDATE' : 'SELECT id FROM businesses WHERE owner_id = $1 ORDER BY id LIMIT 1 FOR UPDATE', [input.businessId ?? input.holderId]);
    if (!business.rows[0]) throw new Error('Business not found');
    const recipient = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.recipientId]);
    if (!recipient.rows[0]) throw new Error('Recipient Human not found');
    const holding = await tx.query<{ shares: string }>('SELECT shares FROM business_shares WHERE business_id = $1 AND holder_id = $2 FOR UPDATE', [business.rows[0].id, input.holderId]);
    if (!holding.rows[0] || Number(holding.rows[0].shares) < input.shares) throw new Error('Insufficient shares');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    if (Number(holding.rows[0].shares) === input.shares) await tx.query('DELETE FROM business_shares WHERE business_id = $1 AND holder_id = $2', [business.rows[0].id, input.holderId]);
    else await tx.query('UPDATE business_shares SET shares = shares - $1, updated_at = CURRENT_TIMESTAMP WHERE business_id = $2 AND holder_id = $3', [input.shares, business.rows[0].id, input.holderId]);
    await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,$3) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = business_shares.shares + excluded.shares, updated_at = CURRENT_TIMESTAMP', [business.rows[0].id, input.recipientId, input.shares]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'BUSINESS_SHARES', business.rows[0].id, input.holderId, input.recipientId, input.shares, 'share_transfer', input.correlationId, day]);
    return { ok: true, businessId: business.rows[0].id, from: input.holderId, to: input.recipientId, shares: input.shares, holdings: (await tx.query('SELECT holder_id, shares FROM business_shares WHERE business_id = $1 ORDER BY shares DESC', [business.rows[0].id])).rows, correlationId: input.correlationId };
  });
}

export async function issueShares(repository: PostgresRepository, input: { ownerId: string; businessId: string; recipientId: string; shares: number; pricePerShare: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ amount: string; reason_id: string }>("SELECT amount, reason_id FROM ledger_entries WHERE reason_type = 'share_issuance' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, businessId: input.businessId, total: Number(prior.rows[0].amount), correlationId: input.correlationId };
    const business = await tx.query<{ id: string; owner_id: string }>('SELECT id, owner_id FROM businesses WHERE id = $1 FOR UPDATE', [input.businessId]);
    if (!business.rows[0] || business.rows[0].owner_id !== input.ownerId) throw new Error('Only the Business owner may issue shares');
    const recipient = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.recipientId]);
    if (!recipient.rows[0]) throw new Error('Recipient Human not found');
    const totalCents = marketValueToCents(input.shares, input.pricePerShare);
    const total = centsToMoney(totalCents);
    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' ORDER BY owner_id FOR UPDATE", [input.recipientId, input.ownerId]);
    const buyer = accounts.rows.find((row) => row.owner_id === input.recipientId);
    const owner = accounts.rows.find((row) => row.owner_id === input.ownerId);
    if (!buyer || !owner || moneyToCents(buyer.balance) < totalCents) throw new Error('Recipient has insufficient Credits');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: buyer.account_id, creditAccount: owner.account_id, amount: total, reasonType: 'share_issuance', reasonId: input.businessId, ruleVersion: 'shares-v2', correlationId: input.correlationId });
    await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,$3) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = business_shares.shares + excluded.shares, updated_at = CURRENT_TIMESTAMP', [input.businessId, input.recipientId, input.shares]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'BUSINESS_SHARES', input.businessId, input.ownerId, input.recipientId, input.shares, 'share_issuance', input.correlationId, day]);
    return { ok: true, businessId: input.businessId, recipientId: input.recipientId, shares: input.shares, pricePerShare: input.pricePerShare, total: Number(total), correlationId: input.correlationId, holdings: (await tx.query('SELECT holder_id, shares FROM business_shares WHERE business_id = $1 ORDER BY shares DESC', [input.businessId])).rows };
  });
}

export async function setPolicy(repository: PostgresRepository, input: { humanId: string; policy: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const business = await tx.query<{ id: string }>('SELECT businesses.id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.owner_id = $1 OR business_management.manager_id = $1 ORDER BY businesses.id LIMIT 1 FOR UPDATE', [input.humanId]);
    if (!business.rows[0]) throw new Error('No managed business is available to this Human');
    await tx.query('UPDATE businesses SET policy = $1 WHERE id = $2', [input.policy, business.rows[0].id]);
    return { ok: true, policy: input.policy, business: (await tx.query('SELECT * FROM businesses WHERE id = $1', [business.rows[0].id])).rows[0] };
  });
}

export async function liquidateBusiness(repository: PostgresRepository, input: { ownerId: string; businessId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM bankruptcy_events WHERE institution_id = $1 AND correlation_id = $2 LIMIT 1', [input.businessId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, businessId: input.businessId, releasedMachines: 0, correlationId: input.correlationId };
    const business = await tx.query<{ id: string; owner_id: string; status: string; financial_status: string | null }>(
      "SELECT businesses.id, businesses.owner_id, businesses.status, financial_states.status AS financial_status FROM businesses LEFT JOIN financial_states ON financial_states.institution_id = businesses.id WHERE businesses.id = $1 FOR UPDATE",
      [input.businessId],
    );
    if (!business.rows[0]) throw new Error('Business not found');
    if (business.rows[0].owner_id !== input.ownerId) throw new Error('Only the Business owner may liquidate it');
    if (business.rows[0].status === 'bankrupt' || business.rows[0].financial_status === 'dissolved') return { ok: true, alreadyProcessed: true, businessId: input.businessId, releasedMachines: 0, correlationId: input.correlationId };
    if (!['distressed', 'insolvent'].includes(business.rows[0].status) && !['distressed', 'insolvent'].includes(business.rows[0].financial_status ?? '')) throw new Error('Business must be distressed or insolvent before liquidation');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const machines = await tx.query<{ machine_id: string }>('SELECT machine_id FROM business_assets WHERE business_id = $1 FOR UPDATE', [input.businessId]);
    await tx.query('UPDATE machines SET utilization = 0 WHERE id IN (SELECT machine_id FROM business_assets WHERE business_id = $1)', [input.businessId]);
    await tx.query('DELETE FROM business_assets WHERE business_id = $1', [input.businessId]);
    await tx.query("UPDATE businesses SET status = 'bankrupt' WHERE id = $1", [input.businessId]);
    await tx.query("UPDATE institutions SET status = 'dissolved' WHERE id = $1", [input.businessId]);
    await tx.query("UPDATE financial_states SET status = 'dissolved', recovery_game_day = $1, last_reason = 'Owner-authorized business liquidation', updated_at = CURRENT_TIMESTAMP WHERE institution_id = $2 AND status IN ('distressed','insolvent')", [day, input.businessId]);
    const eventId = `BUSINESS-LIQUIDATION-${input.businessId}-${day}`;
    await tx.query("INSERT INTO bankruptcy_events (id,institution_id,institution_kind,from_status,to_status,game_day,reason,correlation_id) VALUES ($1,$2,'BUSINESS',$3,'dissolved',$4,$5,$6) ON CONFLICT (id) DO NOTHING", [eventId, input.businessId, business.rows[0].financial_status ?? business.rows[0].status, day, 'Owner-authorized business liquidation', input.correlationId]);
    await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'business.liquidated',$3,$4) ON CONFLICT (id) DO NOTHING", [eventId, day, `Business ${input.businessId} was liquidated`, JSON.stringify({ businessId: input.businessId, releasedMachines: machines.rows.length, ownerId: input.ownerId })]);
    await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'business',$3,$4,$5) ON CONFLICT DO NOTHING", [crypto.randomUUID(), input.ownerId, 'Business liquidation recorded', `${input.businessId} was closed. ${machines.rows.length} productive machine(s) were detached and preserved under your Human ownership for future disposition.`, input.businessId]);
    return { ok: true, businessId: input.businessId, releasedMachines: machines.rows.length, gameDay: day, correlationId: input.correlationId };
  });
}

export async function appointManager(repository: PostgresRepository, input: { ownerId: string; businessId: string; managerId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const business = await tx.query<{ id: string; owner_id: string }>('SELECT id, owner_id FROM businesses WHERE id = $1 FOR UPDATE', [input.businessId]);
    if (!business.rows[0]) throw new Error('Business not found');
    if (business.rows[0].owner_id !== input.ownerId) throw new Error('Only the Business owner may appoint its manager');
    if (!(await tx.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.managerId])).rows[0]) throw new Error('Active manager Human not found');
    const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    await tx.query('INSERT INTO business_management (business_id, manager_id, appointed_by, appointed_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(business_id) DO UPDATE SET manager_id = EXCLUDED.manager_id, appointed_by = EXCLUDED.appointed_by, appointed_game_day = EXCLUDED.appointed_game_day, updated_at = CURRENT_TIMESTAMP', [input.businessId, input.managerId, input.ownerId, day]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.manager_appointed', `Manager appointed for ${input.businessId}`, JSON.stringify({ businessId: input.businessId, managerId: input.managerId, appointedBy: input.ownerId })]);
    return { ok: true, management: (await tx.query('SELECT * FROM business_management WHERE business_id = $1', [input.businessId])).rows[0] };
  });
}

export async function updateConstitution(repository: PostgresRepository, input: { ownerId: string; businessId: string; shareholderVoteThreshold: number; boardApprovalThreshold: number; dilutionNoticeDays: number }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const business = await tx.query<{ id: string; owner_id: string }>('SELECT id, owner_id FROM businesses WHERE id = $1 FOR UPDATE', [input.businessId]);
    if (!business.rows[0]) throw new Error('Business not found');
    if (business.rows[0].owner_id !== input.ownerId) throw new Error('Only the Business owner may update its constitution');
    const current = await tx.query<{ version: number }>('SELECT version FROM business_constitutions WHERE business_id = $1', [input.businessId]);
    const version = Number(current.rows[0]?.version ?? 0) + 1;
    const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    await tx.query('INSERT INTO business_constitutions (business_id,version,shareholder_vote_threshold,board_approval_threshold,dilution_notice_days,updated_by,updated_game_day) VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(business_id) DO UPDATE SET version=EXCLUDED.version, shareholder_vote_threshold=EXCLUDED.shareholder_vote_threshold, board_approval_threshold=EXCLUDED.board_approval_threshold, dilution_notice_days=EXCLUDED.dilution_notice_days, updated_by=EXCLUDED.updated_by, updated_game_day=EXCLUDED.updated_game_day, updated_at=CURRENT_TIMESTAMP', [input.businessId, version, input.shareholderVoteThreshold, input.boardApprovalThreshold, input.dilutionNoticeDays, input.ownerId, day]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.constitution_changed', `Business Constitution updated for ${input.businessId}`, JSON.stringify({ businessId: input.businessId, version, updatedBy: input.ownerId })]);
    return { ok: true, constitution: (await tx.query('SELECT * FROM business_constitutions WHERE business_id = $1', [input.businessId])).rows[0] };
  });
}

export async function ownershipRegistry(repository: PostgresRepository, businessId: string): Promise<Record<string, unknown>> {
  const business = await repository.query<{ id: string; name: string; owner_id: string }>('SELECT id, name, owner_id FROM businesses WHERE id = $1', [businessId]);
  if (!business.rows[0]) throw new Error('Business not found');
  const holders = await repository.query<{ holder_id: string; display_name: string; shares: string }>('SELECT business_shares.holder_id, humans.display_name, business_shares.shares FROM business_shares JOIN humans ON humans.id = business_shares.holder_id WHERE business_shares.business_id = $1 ORDER BY business_shares.shares DESC, business_shares.holder_id', [businessId]);
  const total = holders.rows.reduce((sum, holder) => sum + Number(holder.shares), 0);
  return { business: business.rows[0], totalIssuedShares: total, controllingHumanId: holders.rows[0]?.holder_id ?? null, holders: holders.rows.map((holder) => ({ ...holder, percentage: total > 0 ? Math.round(Number(holder.shares) / total * 10000) / 100 : 0 })), ownershipAndManagementAreSeparate: true };
}
