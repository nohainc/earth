import type { PostgresRepository } from './repository';

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

    const accounts = await tx.query<{ account_id: string; owner_id: string; balance: string }>("SELECT account_id, owner_id, balance FROM account_balances WHERE owner_id IN ($1, $2) AND currency = 'CREDIT' FOR UPDATE", [input.predecessorId, input.successorId]);
    const predecessorAccount = accounts.rows.find((account) => account.owner_id === input.predecessorId);
    const successorAccount = accounts.rows.find((account) => account.owner_id === input.successorId);
    if (!predecessorAccount || !successorAccount) throw new Error('Predecessor and successor Credit accounts are required');
    const gross = Math.max(0, Number(predecessorAccount.balance));
    const tax = Math.round(gross * 0.2 * 100) / 100;
    const inherited = Math.max(0, gross - tax);

    await tx.query('UPDATE account_balances SET balance = 0 WHERE account_id = $1', [predecessorAccount.account_id]);
    await tx.query('UPDATE account_balances SET balance = balance + $1 WHERE account_id = $2', [inherited, successorAccount.account_id]);
    if (tax > 0) await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE account_id = 'account-ouc-treasury'", [tax]);
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
    await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,\'CREDIT\',\'late_inheritance\',$6,\'life-v3\',$7)', [crypto.randomUUID(), input.day, predecessorAccount.account_id, successorAccount.account_id, inherited, eventId, eventId]);
    if (tax > 0) await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,\'account-ouc-treasury\',$4,\'CREDIT\',\'late_inheritance_tax\',$5,\'life-v3\',$6)', [crypto.randomUUID(), input.day, predecessorAccount.account_id, tax, eventId, `TAX-${eventId}`]);
    for (const machine of machines.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'MACHINE\',$2,$3,$4,1,\'late_inheritance\',$5,$6)', [crypto.randomUUID(), machine.id, input.predecessorId, input.successorId, eventId, input.day]);
    for (const business of businesses.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'BUSINESS\',$2,$3,$4,1,\'late_inheritance\',$5,$6)', [crypto.randomUUID(), business.id, input.predecessorId, input.successorId, eventId, input.day]);
    for (const share of shares.rows) await tx.query('INSERT INTO ownership_events (id, asset_type, asset_id, from_owner_id, to_owner_id, quantity, reason_type, reason_id, game_day) VALUES ($1,\'BUSINESS_SHARES\',$2,$3,$4,$5,\'late_inheritance\',$6,$7)', [crypto.randomUUID(), share.business_id, input.predecessorId, input.successorId, share.shares, eventId, input.day]);
    await tx.query('INSERT INTO notifications (id, human_id, notification_type, title, body, entity_id) VALUES ($1,$2,\'life\',\'Inheritance received\',$3,$4)', [crypto.randomUUID(), input.successorId, `You received ${inherited} Credits and the registered assets of ${predecessor.rows[0].display_name}.`, eventId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,\'human.life_event\',\'An Estate completed succession\',$3) ON CONFLICT (id) DO NOTHING', [`LATE-INHERITANCE-${input.predecessorId}-${input.day}`, input.day, JSON.stringify({ predecessor: input.predecessorId, successor: input.successorId, inherited, tax })]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [input.predecessorId]);
    return { ok: true, lateSuccession: true, successorHumanId: input.successorId, inherited, tax, eventId, assets: { machines: machines.rows.length, businesses: businesses.rows.length, shareLots: shares.rows.length, resourceTypes: resources.rows.length } };
  });
}

export async function liquidateExpiredEstates(repository: PostgresRepository, day: number): Promise<number> {
  const estates = await repository.query<{ id: string; display_name: string; standing: number; legacy: number; balance: string }>("SELECT humans.id, humans.display_name, humans.standing, humans.legacy, COALESCE(account_balances.balance, 0) AS balance FROM humans JOIN succession_plans ON succession_plans.human_id = humans.id LEFT JOIN account_balances ON account_balances.owner_id = humans.id AND account_balances.currency = 'CREDIT' WHERE humans.life_status = 'estate' AND humans.death_game_day + succession_plans.estate_period_days <= $1", [day]);
  let processed = 0;
  for (const estate of estates.rows) {
    await repository.transaction(async (tx) => {
      const businesses = await tx.query<{ id: string }>('SELECT id FROM businesses WHERE owner_id = $1 FOR UPDATE', [estate.id]);
      const balance = Math.max(0, Number(estate.balance));
      if (balance > 0) {
        await tx.query("UPDATE account_balances SET balance = 0 WHERE owner_id = $1 AND currency = 'CREDIT'", [estate.id]);
        await tx.query("UPDATE account_balances SET balance = balance + $1 WHERE account_id = 'account-ouc-treasury'", [balance]);
        await tx.query('INSERT INTO ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, rule_version, correlation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', [crypto.randomUUID(), day, estate.id, 'account-ouc-treasury', balance, 'CREDIT', 'estate_liquidation', estate.id, 'life-v2', `ESTATE-LIQUIDATION-${estate.id}-${day}`]);
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
