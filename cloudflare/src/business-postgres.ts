import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, marketValueToCents, moneyToCents } from './money.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { toNanoMarkup, fromNanoMarkup } from './nano-markup.ts';
import { businessSectorAccess } from './business-rules.ts';

const sectors = new Set([
  'energy', 'extraction', 'components', 'machines', 'maintenance', 'housing',
  'compute', 'r-and-d', 'it-services', 'consulting', 'logistics', 'healthcare',
  'education',
]);

export async function createBusiness(repository: PostgresRepository, input: { ownerId: string; name: string; sector: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ reason_id: string }>("SELECT reason_id FROM ledger_entries WHERE reason_type = 'business_registration' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, business: (await tx.query('SELECT * FROM businesses WHERE id = $1', [prior.rows[0].reason_id])).rows[0], shares: 100, correlationId: input.correlationId };
    if (!sectors.has(input.sector)) throw new Error('Business sector is invalid');
    const membership = await tx.query<{ city_id: string | null; corporation_id: string | null }>('SELECT city_id, corporation_id FROM memberships WHERE human_id = $1', [input.ownerId]);
    const affiliation = membership.rows[0];
    const access = businessSectorAccess(input.sector, Boolean(affiliation?.city_id), Boolean(affiliation?.corporation_id));
    if (!access.allowed) throw new Error(access.reason);
    const nameConflict = await tx.query('SELECT id FROM institutions WHERE name = $1', [input.name]);
    if (nameConflict.rows[0]) throw new Error('Business name already exists');
    const account = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.ownerId]);
    const dynastyPerk = await tx.query<{ perk_key: string }>("SELECT dp.perk_key FROM auth_credentials ac JOIN dynasties d ON d.email = ac.email JOIN dynasty_perks dp ON dp.dynasty_id = d.id WHERE ac.human_id = $1 AND dp.perk_key = 'industrialist_lineage' LIMIT 1", [input.ownerId]);
    const feeCents = dynastyPerk.rows[0] ? 21250n : 25000n;
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
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.formed', `${input.name} was registered`, toNanoMarkup({ businessId, sector: input.sector, founder: input.ownerId })]);
    return { ok: true, business: (await tx.query('SELECT * FROM businesses WHERE id = $1', [businessId])).rows[0], shares: 100, fee: Number(fee), correlationId: input.correlationId };
  });
}

export async function renameBusiness(repository: PostgresRepository, input: { ownerId: string; businessId: string; name: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const business = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE id = $1 AND owner_id = $2', [input.businessId, input.ownerId]);
    if (!business.rows[0]) throw new Error('Only the business owner can rename this business');
    const conflict = await tx.query('SELECT id FROM institutions WHERE name = $1 AND id <> $2', [input.name, input.businessId]);
    if (conflict.rows[0]) throw new Error('Business name already exists');
    await tx.query('UPDATE businesses SET name = $1 WHERE id = $2', [input.name, input.businessId]);
    await tx.query('UPDATE institutions SET name = $1 WHERE id = $2', [input.name, input.businessId]);
    return { ok: true, businessId: input.businessId, name: input.name };
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
    const constitution = await tx.query<{ shareholder_vote_threshold: string }>('SELECT shareholder_vote_threshold FROM business_constitutions WHERE business_id = $1', [input.businessId]);
    const threshold = Number(constitution.rows[0]?.shareholder_vote_threshold ?? 0.667);
    const allShares = await tx.query<{ holder_id: string; shares: string }>('SELECT holder_id, shares FROM business_shares WHERE business_id = $1', [input.businessId]);
    const totalExisting = allShares.rows.reduce((sum, r) => sum + Number(r.shares), 0);
    const ownerShares = Number(allShares.rows.find((r) => r.holder_id === input.ownerId)?.shares ?? 0);
    if (allShares.rows.length > 1 && totalExisting > 0 && ownerShares / totalExisting < threshold) {
      throw new Error('Supermajority shareholder approval required for dilution');
    }
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: buyer.account_id, creditAccount: owner.account_id, amount: total, reasonType: 'share_issuance', reasonId: input.businessId, ruleVersion: 'shares-v2', correlationId: input.correlationId });
    await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,$3) ON CONFLICT(business_id, holder_id) DO UPDATE SET shares = business_shares.shares + excluded.shares, updated_at = CURRENT_TIMESTAMP', [input.businessId, input.recipientId, input.shares]);
    await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)', [crypto.randomUUID(), 'BUSINESS_SHARES', input.businessId, input.ownerId, input.recipientId, input.shares, 'share_issuance', input.correlationId, day]);
    return { ok: true, businessId: input.businessId, recipientId: input.recipientId, shares: input.shares, pricePerShare: input.pricePerShare, total: Number(total), correlationId: input.correlationId, holdings: (await tx.query('SELECT holder_id, shares FROM business_shares WHERE business_id = $1 ORDER BY shares DESC', [input.businessId])).rows };
  });
}

export async function distributeDividends(repository: PostgresRepository, input: { callerId: string; businessId: string; totalAmount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'dividend_payout' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, businessId: input.businessId, totalAmount: input.totalAmount, correlationId: input.correlationId };
    const business = await tx.query<{ id: string; owner_id: string }>('SELECT id, owner_id FROM businesses WHERE id = $1 FOR UPDATE', [input.businessId]);
    if (!business.rows[0]) throw new Error('Business not found');
    const management = await tx.query<{ manager_id: string }>('SELECT manager_id FROM business_management WHERE business_id = $1', [input.businessId]);
    const isManager = management.rows[0]?.manager_id === input.callerId;
    const isOwner = business.rows[0].owner_id === input.callerId;
    if (!isOwner && !isManager) throw new Error('Only the Business owner or appointed manager may distribute dividends');
    const totalCents = moneyToCents(input.totalAmount);
    if (totalCents <= 0n) throw new Error('Dividend amount must be positive');
    const sourceAccount = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [business.rows[0].owner_id]);
    if (!sourceAccount.rows[0] || moneyToCents(sourceAccount.rows[0].balance) < totalCents) throw new Error('Insufficient operating balance for dividend distribution');
    const shares = await tx.query<{ holder_id: string; shares: string }>('SELECT holder_id, shares FROM business_shares WHERE business_id = $1 ORDER BY shares DESC FOR UPDATE', [input.businessId]);
    if (!shares.rows.length) throw new Error('No shareholders registered');
    const totalShares = shares.rows.reduce((sum, row) => sum + BigInt(row.shares), 0n);
    if (totalShares <= 0n) throw new Error('Total shares count is invalid');
    const financialDynasties = await tx.query<{ human_id: string }>("SELECT ac.human_id FROM auth_credentials ac JOIN dynasties d ON d.email = ac.email JOIN dynasty_perks dp ON dp.dynasty_id = d.id WHERE dp.perk_key = 'financial_magnate' AND ac.human_id = ANY($1::text[])", [shares.rows.map((row) => row.holder_id)]);
    const financialHolders = new Set(financialDynasties.rows.map((row) => row.human_id));
    const standardHeirs = await tx.query<{ human_id: string }>("SELECT equipped_by_human_id AS human_id FROM dynasty_heirlooms WHERE heirloom_type = 'dynasty_standard' AND equipped_by_human_id = ANY($1::text[])", [shares.rows.map((row) => row.holder_id)]);
    const standardHolders = new Set(standardHeirs.rows.map((row) => row.human_id));
    const weightedShares = shares.rows.reduce((sum, row) => sum + BigInt(row.shares) * (financialHolders.has(row.holder_id) ? 108n : 100n) * (standardHolders.has(row.holder_id) ? 105n : 100n), 0n);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    let distributedCents = 0n;
    const payouts: Array<{ holderId: string; amount: number; shares: number }> = [];
    for (let i = 0; i < shares.rows.length; i++) {
      const row = shares.rows[i];
      const rowShares = BigInt(row.shares);
      const adjustedShares = rowShares * (financialHolders.has(row.holder_id) ? 108n : 100n) * (standardHolders.has(row.holder_id) ? 105n : 100n);
      const holderCents = i === shares.rows.length - 1 ? totalCents - distributedCents : (totalCents * adjustedShares) / weightedShares;
      if (holderCents <= 0n) continue;
      distributedCents += holderCents;
      const holderAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [row.holder_id]);
      if (!holderAccount.rows[0]) continue;
      const payoutAmount = centsToMoney(holderCents);
      const subCorrelation = `${input.correlationId}-${row.holder_id}`;
      await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: sourceAccount.rows[0].account_id, creditAccount: holderAccount.rows[0].account_id, amount: payoutAmount, reasonType: 'dividend_payout', reasonId: input.businessId, ruleVersion: 'dividends-v1', correlationId: subCorrelation });
      payouts.push({ holderId: row.holder_id, amount: Number(payoutAmount), shares: Number(row.shares) });
      await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [crypto.randomUUID(), row.holder_id, 'business', 'Dividend payout received', `You received ${payoutAmount} Credits in dividend distribution from ${input.businessId}.`, input.businessId]);
    }
    await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [centsToMoney(totalCents), day, input.businessId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.dividend_distributed', `Dividends distributed for ${input.businessId}`, toNanoMarkup({ businessId: input.businessId, totalAmount: input.totalAmount, recipientsCount: payouts.length, correlationId: input.correlationId })]);
    await enqueueOutbox(tx, {
      eventKey: `business-dividend:${input.correlationId}`,
      topic: 'world_activity',
      aggregateType: 'business',
      aggregateId: input.businessId,
      payload: { type: 'world_activity', category: 'business', action: 'dividend_distributed', businessId: input.businessId, totalAmount: input.totalAmount, recipientsCount: payouts.length, gameDay: day },
    });
    return { ok: true, businessId: input.businessId, totalAmount: input.totalAmount, distributions: payouts, correlationId: input.correlationId };
  });
}

export async function setPolicy(repository: PostgresRepository, input: { humanId: string; businessId?: string | null; policy: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const business = input.businessId
      ? await tx.query<{ id: string }>('SELECT businesses.id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.id = $1 AND businesses.status = \'active\' AND (businesses.owner_id = $2 OR business_management.manager_id = $2) FOR UPDATE OF businesses', [input.businessId, input.humanId])
      : await tx.query<{ id: string }>('SELECT businesses.id FROM businesses LEFT JOIN business_management ON business_management.business_id = businesses.id WHERE businesses.owner_id = $1 OR business_management.manager_id = $1 ORDER BY businesses.id LIMIT 1 FOR UPDATE OF businesses', [input.humanId]);
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
      "SELECT businesses.id, businesses.owner_id, businesses.status, financial_states.status AS financial_status FROM businesses LEFT JOIN financial_states ON financial_states.institution_id = businesses.id WHERE businesses.id = $1 FOR UPDATE OF businesses",
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
    await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'business.liquidated',$3,$4) ON CONFLICT (id) DO NOTHING", [eventId, day, `Business ${input.businessId} was liquidated`, toNanoMarkup({ businessId: input.businessId, releasedMachines: machines.rows.length, ownerId: input.ownerId })]);
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
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.manager_appointed', `Manager appointed for ${input.businessId}`, toNanoMarkup({ businessId: input.businessId, managerId: input.managerId, appointedBy: input.ownerId })]);
    return { ok: true, management: (await tx.query('SELECT * FROM business_management WHERE business_id = $1', [input.businessId])).rows[0] };
  });
}

async function managedBusiness(tx: PostgresRepository, humanId: string, businessId: string) {
  const result = await tx.query<{ id: string; owner_id: string }>(
    'SELECT b.id, b.owner_id FROM businesses b LEFT JOIN business_management bm ON bm.business_id = b.id WHERE b.id = $1 AND (b.owner_id = $2 OR bm.manager_id = $2) FOR UPDATE OF b',
    [businessId, humanId],
  );
  if (!result.rows[0]) throw new Error('Business management access denied');
  return result.rows[0];
}

export async function hireEmployee(repository: PostgresRepository, input: { humanId: string; businessId: string; name: string; role: string; wage: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await managedBusiness(tx, input.humanId, input.businessId);
    if (input.name.trim().length < 2 || input.role.trim().length < 2) throw new Error('Employee name and role are required');
    if (!Number.isFinite(input.wage) || input.wage <= 0) throw new Error('Employee wage must be positive');
    const prior = await tx.query<{ id: string }>('SELECT id FROM business_employees WHERE id = $1', [`EMP-${input.correlationId}`]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, employeeId: prior.rows[0].id, correlationId: input.correlationId };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const employeeId = `EMP-${input.correlationId}`;
    await tx.query('INSERT INTO business_employees (id,business_id,name,role,wage,hired_game_day) VALUES ($1,$2,$3,$4,$5,$6)', [employeeId, input.businessId, input.name.trim(), input.role.trim(), input.wage, day]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [`WORKFORCE-HIRE-${input.correlationId}`, day, 'business.employee_hired', `${input.name.trim()} joined the business`, toNanoMarkup({ businessId: input.businessId, employeeId, role: input.role.trim(), wage: input.wage, correlationId: input.correlationId })]);
    return { ok: true, employeeId, businessId: input.businessId, correlationId: input.correlationId };
  });
}

export async function trainEmployee(repository: PostgresRepository, input: { humanId: string; businessId: string; employeeId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await managedBusiness(tx, input.humanId, input.businessId);
    const affiliation = await tx.query<{ city_id: string | null }>('SELECT city_id FROM memberships WHERE human_id = $1', [input.humanId]);
    if (!affiliation.rows[0]?.city_id) throw new Error('Staff training requires an active city affiliation');
    const employee = await tx.query<{ id: string; skill: string; morale: string; status: string }>('SELECT id, skill, morale, status FROM business_employees WHERE id = $1 AND business_id = $2 FOR UPDATE', [input.employeeId, input.businessId]);
    if (!employee.rows[0] || employee.rows[0].status !== 'active') throw new Error('Active employee not found');
    const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [`WORKFORCE-TRAIN-${input.correlationId}`]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, employeeId: input.employeeId, correlationId: input.correlationId };
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const cost = 120;
    await tx.query('UPDATE business_employees SET skill = LEAST(1, skill + 0.05), morale = GREATEST(0, morale - 0.01), updated_at = CURRENT_TIMESTAMP WHERE id = $1', [input.employeeId]);
    await tx.query('UPDATE business_financials SET operating_costs = operating_costs + $1, profit = profit - $1, last_game_day = $2, updated_at = CURRENT_TIMESTAMP WHERE business_id = $3', [cost, day, input.businessId]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [`WORKFORCE-TRAIN-${input.correlationId}`, day, 'business.employee_trained', `Training completed for ${input.employeeId}`, toNanoMarkup({ businessId: input.businessId, employeeId: input.employeeId, cost, correlationId: input.correlationId })]);
    return { ok: true, employeeId: input.employeeId, cost, correlationId: input.correlationId };
  });
}

export async function dismissEmployee(repository: PostgresRepository, input: { humanId: string; businessId: string; employeeId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await managedBusiness(tx, input.humanId, input.businessId);
    const employee = await tx.query<{ id: string; name: string }>('SELECT id, name FROM business_employees WHERE id = $1 AND business_id = $2 FOR UPDATE', [input.employeeId, input.businessId]);
    if (!employee.rows[0]) throw new Error('Employee not found');
    const eventId = `WORKFORCE-DISMISS-${input.correlationId}`;
    const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [eventId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, employeeId: input.employeeId, correlationId: input.correlationId };
    const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    await tx.query("UPDATE business_employees SET status = 'dismissed', updated_at = CURRENT_TIMESTAMP WHERE id = $1", [input.employeeId]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [eventId, day, 'business.employee_dismissed', `${employee.rows[0].name} left the business`, toNanoMarkup({ businessId: input.businessId, employeeId: input.employeeId, correlationId: input.correlationId })]);
    return { ok: true, employeeId: input.employeeId, name: employee.rows[0].name, day, correlationId: input.correlationId };
  });
}

export async function reassignEmployee(repository: PostgresRepository, input: { humanId: string; businessId: string; employeeId: string; role: string; wage: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    await managedBusiness(tx, input.humanId, input.businessId);
    const role = input.role.trim();
    if (role.length < 2 || role.length > 80) throw new Error('Employee role is invalid');
    if (!Number.isFinite(input.wage) || input.wage <= 0) throw new Error('Employee wage must be positive');
    const employee = await tx.query<{ id: string; name: string; role: string; wage: string; status: string }>('SELECT id, name, role, wage, status FROM business_employees WHERE id = $1 AND business_id = $2 FOR UPDATE', [input.employeeId, input.businessId]);
    if (!employee.rows[0] || employee.rows[0].status !== 'active') throw new Error('Active employee not found');
    const eventId = `WORKFORCE-REASSIGN-${input.correlationId}`;
    const prior = await tx.query('SELECT id FROM world_events WHERE id = $1', [eventId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, employeeId: input.employeeId, correlationId: input.correlationId };
    const day = Number((await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 0);
    await tx.query('UPDATE business_employees SET role = $1, wage = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3', [role, input.wage, input.employeeId]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [eventId, day, 'business.employee_reassigned', `${employee.rows[0].name} changed role`, toNanoMarkup({ businessId: input.businessId, employeeId: input.employeeId, oldRole: employee.rows[0].role, role, oldWage: Number(employee.rows[0].wage), wage: input.wage, correlationId: input.correlationId })]);
    return { ok: true, employeeId: input.employeeId, role, wage: input.wage, correlationId: input.correlationId };
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
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.constitution_changed', `Business Constitution updated for ${input.businessId}`, toNanoMarkup({ businessId: input.businessId, version, updatedBy: input.ownerId })]);
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

export async function proposeMerger(repository: PostgresRepository, input: { acquirerId: string; acquirerBusinessId: string; targetBusinessId: string; pricePerShare: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ id: string }>('SELECT id FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2', [input.acquirerId, input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, mergerId: prior.rows[0].id, correlationId: input.correlationId };
    const [acquirer, target] = await Promise.all([
      tx.query<{ id: string; owner_id: string; status: string }>('SELECT id, owner_id, status FROM businesses WHERE id = $1 FOR UPDATE', [input.acquirerBusinessId]),
      tx.query<{ id: string; owner_id: string; status: string }>('SELECT id, owner_id, status FROM businesses WHERE id = $1 FOR UPDATE', [input.targetBusinessId]),
    ]);
    if (!acquirer.rows[0] || acquirer.rows[0].status !== 'active') throw new Error('Acquiring business not found or inactive');
    if (!target.rows[0] || target.rows[0].status !== 'active') throw new Error('Target business not found or inactive');
    if (acquirer.rows[0].owner_id !== input.acquirerId) throw new Error('Only acquiring business owner may propose merger');
    if (input.acquirerBusinessId === input.targetBusinessId) throw new Error('Cannot merge business with itself');
    const targetShares = await tx.query<{ shares: string }>('SELECT shares FROM business_shares WHERE business_id = $1', [input.targetBusinessId]);
    const totalShares = targetShares.rows.reduce((sum, r) => sum + BigInt(r.shares), 0n);
    if (totalShares <= 0n) throw new Error('Target business has no shares');
    const totalCents = marketValueToCents(Number(totalShares), input.pricePerShare);
    const total = centsToMoney(totalCents);
    const acquirerAccount = await tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [input.acquirerId]);
    if (!acquirerAccount.rows[0] || moneyToCents(acquirerAccount.rows[0].balance) < totalCents) throw new Error('Insufficient Credits to fund merger tender offer');
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    const mergerId = `MERGER-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const terms = { acquirerBusinessId: input.acquirerBusinessId, targetBusinessId: input.targetBusinessId, pricePerShare: input.pricePerShare, totalShares: Number(totalShares), totalAmount: Number(total) };
    await tx.query("INSERT INTO negotiated_contracts (id, kind, proposer_id, counterparty_id, title, amount, status, starts_game_day, ends_game_day, correlation_id) VALUES ($1,'strategic',$2,$3,'Merger Tender Offer',$4,'proposed',$5,$6,$7)", [mergerId, input.acquirerId, target.rows[0].owner_id, total, day, day + 30, input.correlationId]);
    await tx.query("INSERT INTO merger_contracts (contract_id, acquirer_business_id, target_business_id, price_per_share, total_shares, total_amount) VALUES ($1,$2,$3,$4,$5,$6)", [mergerId, input.acquirerBusinessId, input.targetBusinessId, input.pricePerShare, Number(totalShares), total]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), day, 'business.merger_proposed', `Merger tender offer for ${input.targetBusinessId}`, toNanoMarkup({ mergerId, acquirerBusinessId: input.acquirerBusinessId, targetBusinessId: input.targetBusinessId, totalAmount: Number(total) })]);
    await enqueueOutbox(tx, {
      eventKey: `business-merger-proposal:${input.correlationId}`,
      topic: 'world_activity',
      aggregateType: 'business',
      aggregateId: input.acquirerBusinessId,
      payload: { type: 'world_activity', category: 'business', action: 'merger_proposed', mergerId, acquirerBusinessId: input.acquirerBusinessId, targetBusinessId: input.targetBusinessId, gameDay: day },
    });
    return { ok: true, mergerId, terms, correlationId: input.correlationId };
  });
}

export async function executeMerger(repository: PostgresRepository, input: { callerId: string; mergerId: string; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const prior = await tx.query<{ details: string }>("SELECT details FROM world_events WHERE event_type = 'business.merged' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, mergerId: input.mergerId, correlationId: input.correlationId };
    const contract = await tx.query<{ id: string; proposer_id: string; counterparty_id: string; amount: string; status: string }>('SELECT id, proposer_id, counterparty_id, amount, status FROM negotiated_contracts WHERE id = $1 FOR UPDATE', [input.mergerId]);
    if (!contract.rows[0] || contract.rows[0].status === 'cancelled') throw new Error('Merger contract not found or cancelled');
    if (contract.rows[0].counterparty_id !== input.callerId) throw new Error('Only target business owner may accept and execute merger');
    const mergerRecord = await tx.query<{ acquirer_business_id: string; target_business_id: string; price_per_share: string; total_shares: string; total_amount: string }>('SELECT acquirer_business_id, target_business_id, price_per_share, total_shares, total_amount FROM merger_contracts WHERE contract_id = $1 FOR UPDATE', [input.mergerId]);
    if (!mergerRecord.rows[0]) throw new Error('Merger terms not found');
    const acquirerBusinessId = mergerRecord.rows[0].acquirer_business_id;
    const targetBusinessId = mergerRecord.rows[0].target_business_id;
    const totalAmount = Number(mergerRecord.rows[0].total_amount);
    const totalCents = moneyToCents(totalAmount);
    const [acquirerAccount, targetShares] = await Promise.all([
      tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [contract.rows[0].proposer_id]),
      tx.query<{ holder_id: string; shares: string }>('SELECT holder_id, shares FROM business_shares WHERE business_id = $1 ORDER BY shares DESC FOR UPDATE', [targetBusinessId]),
    ]);
    if (!acquirerAccount.rows[0] || moneyToCents(acquirerAccount.rows[0].balance) < totalCents) throw new Error('Acquirer has insufficient Credits to complete merger');
    if (!targetShares.rows.length) throw new Error('Target business has no shares');
    const totalShares = targetShares.rows.reduce((sum, r) => sum + BigInt(r.shares), 0n);
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    let distributedCents = 0n;
    for (let i = 0; i < targetShares.rows.length; i++) {
      const row = targetShares.rows[i];
      const rowShares = BigInt(row.shares);
      const holderCents = i === targetShares.rows.length - 1 ? totalCents - distributedCents : (totalCents * rowShares) / totalShares;
      if (holderCents <= 0n) continue;
      distributedCents += holderCents;
      const holderAccount = await tx.query<{ account_id: string }>("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [row.holder_id]);
      if (holderAccount.rows[0]) {
        const payout = centsToMoney(holderCents);
        await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: acquirerAccount.rows[0].account_id, creditAccount: holderAccount.rows[0].account_id, amount: payout, reasonType: 'merger_acquisition_payout', reasonId: targetBusinessId, ruleVersion: 'merger-v1', correlationId: `${input.correlationId}-${row.holder_id}` });
      }
    }
    const machines = await tx.query<{ machine_id: string }>('SELECT machine_id FROM business_assets WHERE business_id = $1 FOR UPDATE', [targetBusinessId]);
    await tx.query('UPDATE business_assets SET business_id = $1 WHERE business_id = $2', [acquirerBusinessId, targetBusinessId]);
    await tx.query('UPDATE machines SET owner_id = $1 WHERE id IN (SELECT machine_id FROM business_assets WHERE business_id = $2)', [contract.rows[0].proposer_id, acquirerBusinessId]);
    await tx.query("UPDATE businesses SET status = 'bankrupt' WHERE id = $1", [targetBusinessId]);
    await tx.query("UPDATE institutions SET status = 'dissolved' WHERE id = $1", [targetBusinessId]);
    await tx.query("UPDATE negotiated_contracts SET status = 'completed', accepted_game_day = $1 WHERE id = $2", [day, input.mergerId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details, correlation_id) VALUES ($1,$2,$3,$4,$5,$6)', [crypto.randomUUID(), day, 'business.merged', `Business ${targetBusinessId} merged into ${acquirerBusinessId}`, toNanoMarkup({ mergerId: input.mergerId, acquirerBusinessId, targetBusinessId, transferredMachines: machines.rows.length, correlationId: input.correlationId }), input.correlationId]);
    await enqueueOutbox(tx, {
      eventKey: `business-merger:${input.correlationId}`,
      topic: 'world_activity',
      aggregateType: 'business',
      aggregateId: acquirerBusinessId,
      payload: { type: 'world_activity', category: 'business', action: 'business_merged', mergerId: input.mergerId, acquirerBusinessId, targetBusinessId, gameDay: day },
    });
    return { ok: true, mergerId: input.mergerId, acquirerBusinessId, targetBusinessId, transferredMachines: machines.rows.length, correlationId: input.correlationId };
  });
}
