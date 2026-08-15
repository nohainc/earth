import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, moneyToCents, taxToCents } from './money';

export async function registerSuccessor(repository: PostgresRepository, input: { humanId: string; successorName: string; estatePeriodDays: number; successorHumanId: string | null; currentLifeStatus: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (input.currentLifeStatus === 'estate') throw new Error('Estate inheritance requires the succession settlement slice');
    if (input.successorHumanId) {
      const successor = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.successorHumanId]);
      if (!successor.rows[0] || input.successorHumanId === input.humanId) throw new Error('Successor Human must be another active Human');
    }
    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const day = Number(world.rows[0]?.game_day ?? 0);
    await tx.query('INSERT INTO succession_plans (human_id, successor_name, registered_game_day, estate_period_days, successor_human_id) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(human_id) DO UPDATE SET successor_name = excluded.successor_name, registered_game_day = excluded.registered_game_day, estate_period_days = excluded.estate_period_days, successor_human_id = excluded.successor_human_id', [input.humanId, input.successorName, day, input.estatePeriodDays, input.successorHumanId]);
    return { ok: true, successor: (await tx.query('SELECT * FROM succession_plans WHERE human_id = $1', [input.humanId])).rows[0] };
  });
}

export async function getSuccessor(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const result = await repository.query('SELECT * FROM succession_plans WHERE human_id = $1', [humanId]);
  return { successor: result.rows[0] ?? null };
}

export async function getLifeStatus(repository: PostgresRepository, humanId: string): Promise<Record<string, unknown>> {
  const [human, succession, events] = await Promise.all([
    repository.query('SELECT id, display_name, age_years, life_status, death_game_day, standing, legacy FROM humans WHERE id = $1', [humanId]),
    repository.query('SELECT * FROM succession_plans WHERE human_id = $1', [humanId]),
    repository.query('SELECT * FROM life_events WHERE human_id = $1 ORDER BY game_day DESC LIMIT 20', [humanId]),
  ]);
  return { ok: true, human: human.rows[0] ?? null, succession: succession.rows[0] ?? null, events: events.rows };
}

export async function settleInheritance(repository: PostgresRepository, input: { predecessorId: string; successorId: string; successorName: string; day: number }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const eventId = `INHERIT-${input.predecessorId}-${input.day}`;
    const prior = await tx.query<{ estate_credits: string }>("SELECT estate_credits FROM life_events WHERE id = $1 AND event_type = 'inheritance'", [eventId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, eventId, inherited: Number(prior.rows[0].estate_credits), successorHumanId: input.successorId };

    const predecessor = await tx.query<{ id: string; display_name: string; death_game_day: number; standing: number; legacy: number; life_status: string }>('SELECT id, display_name, death_game_day, standing, legacy, life_status FROM humans WHERE id = $1 FOR UPDATE', [input.predecessorId]);
    const successor = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active' FOR UPDATE", [input.successorId]);
    if (!predecessor.rows[0] || predecessor.rows[0].life_status !== 'estate') throw new Error('Only an active Estate can be settled');
    if (!successor.rows[0] || input.successorId === input.predecessorId) throw new Error('Successor Human must be another active Human');

    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT'", [input.predecessorId, input.successorId]);
    const predecessorAccount = accounts.rows.find((account) => account.owner_id === input.predecessorId);
    const successorAccount = accounts.rows.find((account) => account.owner_id === input.successorId);
    if (!predecessorAccount || !successorAccount) throw new Error('Predecessor and successor Credit accounts are required');
    const grossCents = moneyToCents(predecessorAccount.balance);
    const taxCents = taxToCents(predecessorAccount.balance, '0.20');
    const inheritedCents = grossCents - taxCents;
    const gross = Number(centsToMoney(grossCents));
    const tax = Number(centsToMoney(taxCents));
    const inherited = Number(centsToMoney(inheritedCents));
    const transferDay = input.day;
    if (inheritedCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: transferDay, debitAccount: predecessorAccount.account_id, creditAccount: successorAccount.account_id, amount: centsToMoney(inheritedCents), reasonType: 'late_inheritance', reasonId: eventId, ruleVersion: 'life-v4', correlationId: eventId });
    if (taxCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: transferDay, debitAccount: predecessorAccount.account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(taxCents), reasonType: 'late_inheritance_tax', reasonId: eventId, ruleVersion: 'life-v4', correlationId: `TAX-${eventId}` });
    await tx.query('UPDATE humans SET standing = 0, legacy = legacy + 1 WHERE id = $1', [input.successorId]);

    const machines = await tx.query<{ id: string }>('SELECT id FROM machines WHERE owner_id = $1 FOR UPDATE', [input.predecessorId]);
    const businesses = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE owner_id = $1 FOR UPDATE', [input.predecessorId]);
    const shares = await tx.query<{ business_id: string; shares: string }>('SELECT business_id, shares FROM business_shares WHERE holder_id = $1 FOR UPDATE', [input.predecessorId]);
    const resources = await tx.query<{ resource: string; amount: string }>('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 FOR UPDATE', [input.predecessorId]);
    await tx.query('UPDATE machines SET owner_id = $1 WHERE owner_id = $2', [input.successorId, input.predecessorId]);
    await tx.query('UPDATE businesses SET owner_id = $1 WHERE owner_id = $2', [input.successorId, input.predecessorId]);
    for (const share of shares.rows) {
      await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,$3) ON CONFLICT (business_id, holder_id) DO UPDATE SET shares = business_shares.shares + EXCLUDED.shares, updated_at = CURRENT_TIMESTAMP', [share.business_id, input.successorId, share.shares]);
    }
    await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [input.predecessorId]);
    for (const resource of resources.rows) await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [input.successorId, resource.resource, resource.amount]);
    await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [input.predecessorId]);
    await tx.query("UPDATE humans SET life_status = 'deceased' WHERE id = $1", [input.predecessorId]);
    await tx.query('INSERT INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, $1 FROM humans WHERE id = $2 ON CONFLICT (human_id) DO UPDATE SET successor_name = EXCLUDED.successor_name', [input.successorName, input.predecessorId]);
    await tx.query('INSERT INTO life_events (id, human_id, event_type, game_day, successor_name, estate_credits) VALUES ($1,$2,\'inheritance\',$3,$4,$5)', [eventId, input.predecessorId, input.day, input.successorName, inherited]);
    for (const machine of machines.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'MACHINE\',$2,$3,$4,1,\'late_inheritance\',$5,$6)', [crypto.randomUUID(), machine.id, input.predecessorId, input.successorId, eventId, input.day]);
    for (const business of businesses.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'BUSINESS\',$2,$3,$4,1,\'late_inheritance\',$5,$6)', [crypto.randomUUID(), business.id, input.predecessorId, input.successorId, eventId, input.day]);
    for (const share of shares.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'BUSINESS_SHARES\',$2,$3,$4,$5,\'late_inheritance\',$6,$7)', [crypto.randomUUID(), share.business_id, input.predecessorId, input.successorId, share.shares, eventId, input.day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'life\',\'Inheritance received\',$3,$4)', [crypto.randomUUID(), input.successorId, `You received ${inherited} Credits and the registered assets of ${predecessor.rows[0].display_name}.`, eventId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,\'human.life_event\',\'An Estate completed succession\',$3) ON CONFLICT (id) DO NOTHING', [`LATE-INHERITANCE-${input.predecessorId}-${input.day}`, input.day, JSON.stringify({ predecessor: input.predecessorId, successor: input.successorId, inherited, tax })]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [input.predecessorId]);
    return { ok: true, lateSuccession: true, successorHumanId: input.successorId, inherited, tax, eventId, assets: { machines: machines.rows.length, businesses: businesses.rows.length, shareLots: shares.rows.length, resourceTypes: resources.rows.length } };
  });
}

export async function processMortality(tx: PostgresRepository, day: number): Promise<number> {
  const service = await tx.query<{ essential_services_index: string }>("SELECT essential_services_index FROM world_state WHERE id = 'WORLD'");
  const mortalityAge = Math.round(90 + Math.max(-5, Math.min(5, (Number(service.rows[0]?.essential_services_index ?? 0.68) - 0.68) * 10)));
  const humans = await tx.query<{ id: string; account_id: string | null; display_name: string; standing: number; legacy: number; age_years: number; successor_name: string | null; successor_human_id: string | null; estate_period_days: number | null; balance: string }>('SELECT humans.id, account_balances.account_id, humans.display_name, humans.standing, humans.legacy, humans.age_years, succession_plans.successor_name, succession_plans.successor_human_id, succession_plans.estate_period_days, COALESCE(account_balances.balance, 0) AS balance FROM humans LEFT JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = \'CREDIT\' WHERE humans.life_status = \'active\' AND humans.age_years >= $1 FOR UPDATE', [mortalityAge]);
  let processed = 0;
  for (const human of humans.rows) {
    const eventId = `DEATH-${human.id}-${day}`;
    if ((await tx.query("SELECT 1 FROM life_events WHERE id = $1 AND event_type = 'death'", [eventId])).rows[0]) continue;
    const successor = human.successor_human_id ? await tx.query<{ id: string; account_id: string }>("SELECT humans.id, account_balances.account_id FROM humans JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.id = $1 AND humans.life_status = 'active' FOR UPDATE", [human.successor_human_id]) : { rows: [] } as { rows: Array<{ id: string; account_id: string }> };
    const successorRow = successor.rows[0];
    const membership = await tx.query<{ corporation_id: string | null; city_id: string | null }>('SELECT corporation_id, city_id FROM memberships WHERE human_id = $1 FOR UPDATE', [human.id]);
    const membershipRow = membership.rows[0];
    const assets = successorRow ? await tx.query<{ id: string; type: string }>("SELECT id, 'MACHINE' AS type FROM machines WHERE owner_id = $1 UNION ALL SELECT id, 'BUSINESS' FROM businesses WHERE owner_id = $1", [human.id]) : { rows: [] } as { rows: Array<{ id: string; type: string }> };
    const shares = successorRow ? await tx.query<{ business_id: string; shares: string }>('SELECT business_id, shares FROM business_shares WHERE holder_id = $1 FOR UPDATE', [human.id]) : { rows: [] } as { rows: Array<{ business_id: string; shares: string }> };
    const resources = successorRow ? await tx.query<{ resource: string; amount: string }>('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 FOR UPDATE', [human.id]) : { rows: [] } as { rows: Array<{ resource: string; amount: string }> };
    const grossCents = moneyToCents(human.balance);
    const taxCents = successorRow ? taxToCents(human.balance, '0.10') : 0n;
    const inheritedCents = grossCents - taxCents;
    const gross = Number(centsToMoney(grossCents));
    const tax = Number(centsToMoney(taxCents));
    const inherited = Number(centsToMoney(inheritedCents));

    if (successorRow) {
      if (!human.account_id) throw new Error('Deceased Human Credit account is required for inheritance');
      if (inheritedCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: human.account_id, creditAccount: successorRow.account_id, amount: centsToMoney(inheritedCents), reasonType: 'inheritance', reasonId: eventId, ruleVersion: 'life-v4', correlationId: eventId });
      if (taxCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: human.account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(taxCents), reasonType: 'inheritance_tax', reasonId: eventId, ruleVersion: 'life-v4', correlationId: `TAX-${eventId}` });
      await tx.query('UPDATE humans SET legacy = legacy + $1 WHERE id = $2', [Number(human.legacy) + (gross > 0 ? 1 : 0), successorRow.id]);
      await tx.query('UPDATE machines SET owner_id = $1 WHERE owner_id = $2', [successorRow.id, human.id]);
      await tx.query('UPDATE businesses SET owner_id = $1 WHERE owner_id = $2', [successorRow.id, human.id]);
      for (const share of shares.rows) await tx.query('INSERT INTO business_shares (business_id, holder_id, shares) VALUES ($1,$2,$3) ON CONFLICT (business_id, holder_id) DO UPDATE SET shares = business_shares.shares + EXCLUDED.shares, updated_at = CURRENT_TIMESTAMP', [share.business_id, successorRow.id, share.shares]);
      await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [human.id]);
      for (const resource of resources.rows) await tx.query('INSERT INTO resource_balances (owner_id, resource, amount) VALUES ($1,$2,$3) ON CONFLICT (owner_id, resource) DO UPDATE SET amount = resource_balances.amount + EXCLUDED.amount', [successorRow.id, resource.resource, resource.amount]);
      await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [human.id]);
      for (const asset of assets.rows) await tx.query('INSERT INTO ownership_events (id,asset_type,asset_id,from_owner_id,to_owner_id,quantity,reason_type,reason_id,game_day) VALUES ($1,$2,$3,$4,$5,1,\'inheritance\',$6,$7)', [crypto.randomUUID(), asset.type, asset.id, human.id, successorRow.id, eventId, day]);
      for (const share of shares.rows) await tx.query('INSERT INTO ownership_events (id,asset_type,asset_id,from_owner_id,to_owner_id,quantity,reason_type,reason_id,game_day) VALUES ($1,\'BUSINESS_SHARES\',$2,$3,$4,$5,\'inheritance\',$6,$7)', [crypto.randomUUID(), share.business_id, human.id, successorRow.id, share.shares, eventId, day]);
      await tx.query('INSERT INTO life_events (id,human_id,event_type,game_day,successor_name,estate_credits) VALUES ($1,$2,\'inheritance\',$3,$4,$5)', [`INHERIT-${human.id}-${day}`, human.id, day, human.successor_name, inherited]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'life\',\'Inheritance received\',$3,$4)', [crypto.randomUUID(), successorRow.id, `You received ${inherited} Credits and the productive assets of ${human.display_name}.`, eventId]);
    }
    if (membershipRow?.corporation_id) {
      await tx.query('UPDATE corporations SET member_count = GREATEST(0, member_count - 1) WHERE id = $1', [membershipRow.corporation_id]);
      await tx.query('INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,\'CORPORATION\',$3,\'released\',$4,\'mortality\')', [crypto.randomUUID(), human.id, membershipRow.corporation_id, day]);
    }
    if (membershipRow?.city_id) {
      await tx.query('UPDATE cities SET residents = GREATEST(0, residents - 1) WHERE id = $1', [membershipRow.city_id]);
      await tx.query('INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,\'CITY\',$3,\'released\',$4,\'mortality\')', [crypto.randomUUID(), human.id, membershipRow.city_id, day]);
    }
    await tx.query('UPDATE memberships SET city_id = NULL, corporation_id = NULL WHERE human_id = $1', [human.id]);
    await tx.query("UPDATE role_assignments SET status = 'expired' WHERE human_id = $1 AND status = 'active'", [human.id]);
    await tx.query("UPDATE humans SET life_status = $1, death_game_day = $2 WHERE id = $3", [successorRow ? 'deceased' : 'estate', day, human.id]);
    await tx.query('INSERT INTO life_events (id,human_id,event_type,game_day,successor_name,estate_credits) VALUES ($1,$2,\'death\',$3,$4,$5)', [eventId, human.id, day, human.successor_name, successorRow ? gross : gross]);
    if (successorRow) {
      await tx.query('INSERT INTO deceased_profiles (human_id,display_name,death_game_day,final_standing,final_legacy,successor_name) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (human_id) DO UPDATE SET successor_name = EXCLUDED.successor_name', [human.id, human.display_name, day, human.standing, human.legacy, human.successor_name]);
      await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [human.id]);
      await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'human.life_event\',\'A Human entered the archive\',$3) ON CONFLICT (id) DO NOTHING', [`DEATH-${human.id}-${day}`, day, JSON.stringify({ humanId: human.id, successor: human.successor_name })]);
    } else {
      await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,\'human.life_event\',\'A Human entered an Estate Period\',$3) ON CONFLICT (id) DO NOTHING', [`ESTATE-${human.id}-${day}`, day, JSON.stringify({ humanId: human.id, estatePeriodDays: human.estate_period_days ?? 30 })]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,\'life\',\'Estate Period started\',$3,$2)', [crypto.randomUUID(), human.id, `Your estate remains available for ${human.estate_period_days ?? 30} game days before liquidation.`]);
    }
    processed += 1;
  }
  return processed;
}

export async function liquidateExpiredEstates(repository: PostgresRepository, day: number): Promise<number> {
  const estates = await repository.query<{ id: string; account_id: string | null; display_name: string; standing: number; legacy: number; balance: string }>("SELECT humans.id, account_balances.account_id, humans.display_name, humans.standing, humans.legacy, COALESCE(account_balances.balance, 0) AS balance FROM humans JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'estate' AND humans.death_game_day + succession_plans.estate_period_days <= $1", [day]);
  let processed = 0;
  for (const estate of estates.rows) {
    await repository.transaction(async (tx) => {
      const businesses = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE owner_id = $1 FOR UPDATE', [estate.id]);
      const balanceCents = moneyToCents(estate.balance);
      const balance = Number(centsToMoney(balanceCents));
      if (balanceCents > 0n) {
        if (!estate.account_id) throw new Error('Estate Credit account is required for liquidation');
        await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay: day, debitAccount: estate.account_id, creditAccount: 'account-ouc-treasury', amount: centsToMoney(balanceCents), reasonType: 'estate_liquidation', reasonId: estate.id, ruleVersion: 'life-v3', correlationId: `ESTATE-LIQUIDATION-${estate.id}-${day}` });
      }
      await tx.query('DELETE FROM business_assets WHERE machine_id IN (SELECT id FROM machines WHERE owner_id = $1)', [estate.id]);
      await tx.query('DELETE FROM machines WHERE owner_id = $1', [estate.id]);
      for (const business of businesses.rows) await tx.query('DELETE FROM business_shares WHERE business_id = $1', [business.id]);
      await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [estate.id]);
      await tx.query('DELETE FROM businesses WHERE owner_id = $1', [estate.id]);
      for (const business of businesses.rows) await tx.query("DELETE FROM institutions WHERE id = $1 AND kind = 'BUSINESS'", [business.id]);
      await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [estate.id]);
      await tx.query("UPDATE humans SET life_status = 'deceased' WHERE id = $1", [estate.id]);
      await tx.query('INSERT INTO deceased_profiles (human_id, display_name, death_game_day, final_standing, final_legacy, successor_name) SELECT id, display_name, death_game_day, standing, legacy, NULL FROM humans WHERE id = $1 ON CONFLICT (human_id) DO NOTHING', [estate.id]);
      await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [`ESTATE-LIQUIDATION-${estate.id}-${day}`, day, 'human.estate_liquidated', 'An unclaimed estate was liquidated', JSON.stringify({ humanId: estate.id, credits: balance, businessCount: businesses.rows.length })]);
      await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [estate.id]);
    });
    processed += 1;
  }
  return processed;
}
