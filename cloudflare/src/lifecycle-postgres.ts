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
