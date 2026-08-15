import type { PostgresRepository } from './repository';
import { transferCredits } from './financial-postgres';
import { centsToMoney, moneyToCents } from './money';

async function day(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

async function uniqueInstitutionName(repository: PostgresRepository, name: string): Promise<void> {
  const result = await repository.query('SELECT id FROM institutions WHERE lower(name) = lower($1) UNION ALL SELECT id FROM communities WHERE lower(name) = lower($1) LIMIT 1', [name]);
  if (result.rows[0]) throw new Error('Institution name already exists');
}

export async function listCities(repository: PostgresRepository): Promise<Record<string, unknown>> {
  return { cities: (await repository.query('SELECT * FROM cities ORDER BY id')).rows };
}

export async function listCorporations(repository: PostgresRepository): Promise<Record<string, unknown>> {
  return { corporations: (await repository.query('SELECT * FROM corporations ORDER BY id')).rows };
}

export async function createCity(repository: PostgresRepository, input: { founderId: string; communityId: string; name: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const name = input.name.trim();
    if (name.length < 3 || name.length > 80 || !input.communityId) throw new Error('City name and founding Community are required');
    const founder = await tx.query('SELECT human_id FROM community_members WHERE community_id = $1 AND human_id = $2', [input.communityId, input.founderId]);
    if (!founder.rows[0]) throw new Error('Founder must belong to the Community');
    const population = await tx.query<{ count: number }>("SELECT COUNT(*)::integer AS count FROM community_members cm JOIN humans h ON h.id = cm.human_id LEFT JOIN memberships m ON m.human_id = cm.human_id WHERE cm.community_id = $1 AND h.life_status = 'active' AND m.city_id IS NULL", [input.communityId]);
    const residents = Number(population.rows[0]?.count ?? 0);
    if (residents < 10) throw new Error('A City requires at least 10 active Community members');
    await uniqueInstitutionName(tx, name);
    const cityId = `CITY-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const gameDay = await day(tx);
    const members = await tx.query<{ human_id: string }>("SELECT cm.human_id FROM community_members cm JOIN humans h ON h.id = cm.human_id LEFT JOIN memberships m ON m.human_id = cm.human_id WHERE cm.community_id = $1 AND h.life_status = 'active' AND m.city_id IS NULL", [input.communityId]);
    await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1,'CITY',$2,'active')", [cityId, name]);
    await tx.query('INSERT INTO cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury) VALUES ($1,$1,0,0,0,0,50,0)', [cityId]);
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT')", [`account-city-${cityId}`, cityId]);
    await tx.query("INSERT INTO institution_roles (id, institution_id, name, term_days, eligibility) VALUES ($1,$2,'City Mayor',90,'resident'),($3,$2,'Infrastructure Planner',90,'resident')", [`${cityId}-MAYOR`, cityId, `${cityId}-PLANNER`]);
    await tx.query("UPDATE memberships SET city_id = $1 WHERE human_id = ANY($2::text[]) AND city_id IS NULL", [cityId, members.rows.map((member) => member.human_id)]);
    await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1), housing_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = $1), energy_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = $1), connectivity_capacity = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [cityId]);
    for (const member of members.rows) {
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CITY',$3,'joined',$4,'city_formation')", [crypto.randomUUID(), member.human_id, cityId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CITY-FORMED-${member.human_id}-${cityId}`, member.human_id, 'institution', 'City founded', `City ${cityId} was founded and you became a resident.`, cityId]);
    }
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'city.formed', `${name} was founded`, JSON.stringify({ cityId, communityId: input.communityId, residents })]);
    return { ok: true, city: (await tx.query('SELECT * FROM cities WHERE id = $1', [cityId])).rows[0] };
  });
}

export async function cityQualification(repository: PostgresRepository, cityId: string): Promise<Record<string, unknown>> {
  const city = await repository.query<Record<string, unknown>>('SELECT * FROM cities WHERE id = $1', [cityId]);
  if (!city.rows[0]) throw new Error('City not found');
  const role = await repository.query('SELECT id FROM institution_roles WHERE institution_id = $1 AND status = \'active\' LIMIT 1', [String(city.rows[0].institution_id)]);
  const row = city.rows[0];
  const requirements = { activePopulation: Number(row.residents ?? 0) >= 10, housing: Number(row.housing_capacity ?? 0) >= Number(row.residents ?? 0), energy: Number(row.energy_capacity ?? 0) >= Number(row.residents ?? 0), connectivity: Number(row.connectivity_capacity ?? 0) >= Number(row.residents ?? 0), health: Number(row.health_capacity ?? 0) >= 50, treasury: Number(row.treasury ?? 0) >= 0, governance: Boolean(role.rows[0]) };
  return { ok: true, city: row, requirements, qualified: Object.values(requirements).every(Boolean) };
}

export async function createCorporation(repository: PostgresRepository, input: { founderId: string; cityId: string; name: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const name = input.name.trim();
    if (name.length < 3 || name.length > 80 || !input.cityId) throw new Error('Corporation name and founding City are required');
    const city = await tx.query<{ id: string; residents: number }>('SELECT id, residents FROM cities WHERE id = $1', [input.cityId]);
    const founder = await tx.query('SELECT human_id FROM memberships WHERE human_id = $1 AND city_id = $2', [input.founderId, input.cityId]);
    if (!city.rows[0] || !founder.rows[0]) throw new Error('Founder must be a resident of the founding City');
    if (Number(city.rows[0].residents) < 30) throw new Error('A Corporation requires at least 30 active City residents');
    await uniqueInstitutionName(tx, name);
    const corporationId = `CORP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const gameDay = await day(tx);
    const members = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 AND corporation_id IS NULL', [input.cityId]);
    await tx.query("INSERT INTO institutions (id,kind,name,status) VALUES ($1,'CORPORATION',$2,'active')", [corporationId, name]);
    await tx.query('INSERT INTO corporations (id,institution_id,member_count,treasury,constitution_version) VALUES ($1,$1,0,0,1)', [corporationId]);
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT')", [`account-corporation-${corporationId}`, corporationId]);
    await tx.query("INSERT INTO institution_roles (id,institution_id,name,term_days,eligibility) VALUES ($1,$2,'Corporation Executive',90,'member'),($3,$2,'Corporation Treasurer',90,'member'),($4,$2,'OUC Delegate',90,'representative')", [`${corporationId}-EXECUTIVE`, corporationId, `${corporationId}-TREASURER`, `${corporationId}-DELEGATE`]);
    await tx.query('UPDATE memberships SET corporation_id = $1 WHERE city_id = $2 AND corporation_id IS NULL', [corporationId, input.cityId]);
    await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [corporationId]);
    for (const member of members.rows) {
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'corporation_formation')", [crypto.randomUUID(), member.human_id, corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CORP-FORMED-${member.human_id}-${corporationId}`, member.human_id, 'institution', 'Corporation formed', `Corporation ${corporationId} was formed and you became a member.`, corporationId]);
    }
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation.formed', `${name} was formed`, JSON.stringify({ corporationId, cityId: input.cityId, members: Number(city.rows[0].residents) })]);
    return { ok: true, corporation: (await tx.query('SELECT * FROM corporations WHERE id = $1', [corporationId])).rows[0] };
  });
}

export async function corporationQualification(repository: PostgresRepository, corporationId: string): Promise<Record<string, unknown>> {
  const corporation = await repository.query<Record<string, unknown>>('SELECT * FROM corporations WHERE id = $1', [corporationId]);
  if (!corporation.rows[0]) throw new Error('Corporation not found');
  const city = await repository.query<Record<string, unknown>>('SELECT * FROM cities WHERE id = (SELECT city_id FROM memberships WHERE corporation_id = $1 AND city_id IS NOT NULL LIMIT 1)', [corporationId]);
  const role = await repository.query('SELECT id FROM institution_roles WHERE institution_id = $1 AND status = \'active\' LIMIT 1', [String(corporation.rows[0].institution_id)]);
  const row = corporation.rows[0];
  const requirements = { activeMembership: Number(row.member_count ?? 0) >= 30, recognizedCity: Boolean(city.rows[0]), treasury: Number(row.treasury ?? 0) >= 1000, constitution: Number(row.constitution_version ?? 0) >= 1, governance: Boolean(role.rows[0]) };
  return { ok: true, corporation: row, city: city.rows[0] ?? null, requirements, qualified: Object.values(requirements).every(Boolean) };
}

async function refreshPopulation(tx: PostgresRepository, corporationId: string | null, cityIds: Array<string | null>): Promise<void> {
  if (corporationId) await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [corporationId]);
  for (const cityId of [...new Set(cityIds.filter((value): value is string => Boolean(value)))]) {
    await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [cityId]);
  }
}

export async function changeCorporationMembership(repository: PostgresRepository, input: { humanId: string; corporationId: string; action: 'join' | 'leave' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const corporation = await tx.query<{ id: string }>('SELECT id FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]);
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query<{ corporation_id: string | null; city_id: string | null }>('SELECT corporation_id, city_id FROM memberships WHERE human_id = $1 FOR UPDATE', [input.humanId]);
    const current = existing.rows[0] ?? { corporation_id: null, city_id: null };
    const gameDay = await day(tx);
    if (input.action === 'leave') {
      if (current.corporation_id !== input.corporationId) throw new Error('Human is not a member of this corporation');
      await tx.query('UPDATE memberships SET corporation_id = NULL WHERE human_id = $1 AND corporation_id = $2', [input.humanId, input.corporationId]);
      await refreshPopulation(tx, input.corporationId, [current.city_id]);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'left',$4,'voluntary_resignation')", [crypto.randomUUID(), input.humanId, input.corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CORP-LEFT-${input.humanId}-${input.corporationId}-${gameDay}`, input.humanId, 'institution', 'Corporation left', `You left corporation ${input.corporationId}.`, input.corporationId]);
    } else {
      if (current.corporation_id && current.corporation_id !== input.corporationId) throw new Error('Human already belongs to another corporation');
      const city = await tx.query<{ city_id: string }>('SELECT city_id FROM memberships WHERE corporation_id = $1 AND city_id IS NOT NULL LIMIT 1', [input.corporationId]);
      const cityId = current.city_id ?? city.rows[0]?.city_id ?? null;
      await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = COALESCE(memberships.city_id, excluded.city_id)', [input.humanId, input.corporationId, cityId, gameDay]);
      await refreshPopulation(tx, input.corporationId, [cityId]);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'voluntary_membership')", [crypto.randomUUID(), input.humanId, input.corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CORP-JOINED-${input.humanId}-${input.corporationId}-${gameDay}`, input.humanId, 'institution', 'Corporation joined', `You joined corporation ${input.corporationId}.`, input.corporationId]);
    }
    return { ok: true, membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null };
  });
}

export async function changeCityResidency(repository: PostgresRepository, input: { humanId: string; cityId: string; action: 'join' | 'leave'; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const city = await tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const replay = await tx.query<{ action: string; game_day: number }>('SELECT action, game_day FROM membership_events WHERE id = $1 AND human_id = $2 AND institution_id = $3', [input.correlationId, input.humanId, input.cityId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, residency: replay.rows[0].action === 'joined' ? 'resident' : 'independent', correlationId: input.correlationId, gameDay: Number(replay.rows[0].game_day), membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null };
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query<{ city_id: string | null; corporation_id: string | null }>('SELECT city_id, corporation_id FROM memberships WHERE human_id = $1 FOR UPDATE', [input.humanId]);
    const previousCityId = existing.rows[0]?.city_id ?? null;
    const gameDay = await day(tx);
    if (input.action === 'join') {
      await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET city_id = excluded.city_id, joined_game_day = excluded.joined_game_day', [input.humanId, existing.rows[0]?.corporation_id ?? null, input.cityId, gameDay]);
    } else {
      await tx.query('UPDATE memberships SET city_id = NULL WHERE human_id = $1 AND city_id = $2', [input.humanId, input.cityId]);
    }
    await refreshPopulation(tx, null, [previousCityId, input.cityId]);
    const action = input.action === 'join' ? 'joined' : 'left';
    await tx.query('INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,\'CITY\',$3,$4,$5,$6)', [input.correlationId, input.humanId, input.cityId, action, gameDay, input.action === 'join' ? 'voluntary_residency' : 'voluntary_departure']);
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CITY-${action.toUpperCase()}-${input.humanId}-${input.cityId}-${gameDay}`, input.humanId, 'institution', action === 'joined' ? 'City residency established' : 'City residency ended', action === 'joined' ? `You are now a resident of city ${input.cityId}.` : `You left city ${input.cityId}.`, input.cityId]);
    return { ok: true, residency: action === 'joined' ? 'resident' : 'independent', correlationId: input.correlationId, membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null, city: (await tx.query('SELECT id, residents FROM cities WHERE id = $1', [input.cityId])).rows[0] };
  });
}

async function hasRole(tx: PostgresRepository, humanId: string, institutionId: string, names: string[]): Promise<boolean> {
  const result = await tx.query("SELECT role_assignments.id FROM role_assignments JOIN institution_roles ON institution_roles.id = role_assignments.role_id WHERE role_assignments.human_id = $1 AND role_assignments.institution_id = $2 AND role_assignments.status = 'active' AND institution_roles.name = ANY($3::text[]) AND role_assignments.ends_game_day > (SELECT game_day FROM world_state WHERE id = 'WORLD') LIMIT 1", [humanId, institutionId, names]);
  return Boolean(result.rows[0]);
}

export async function setCityBudget(repository: PostgresRepository, input: { humanId: string; cityId: string; category: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.cityId, ['City Mayor', 'Infrastructure Planner']))) throw new Error('An active City Mayor or Infrastructure Planner term is required');
    const city = await tx.query<{ treasury: string }>('SELECT treasury FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const budgetId = `BUDGET-${input.cityId}-${input.category}`;
    const current = await tx.query<{ amount: string }>('SELECT amount FROM budgets WHERE id = $1 FOR UPDATE', [budgetId]);
    const targetCents = moneyToCents(input.amount);
    const currentCents = moneyToCents(current.rows[0]?.amount ?? '0.00');
    const deltaCents = targetCents - currentCents;
    const delta = centsToMoney(deltaCents < 0n ? -deltaCents : deltaCents);
    if (deltaCents > moneyToCents(city.rows[0].treasury)) throw new Error('Budget exceeds city treasury');
    const gameDay = await day(tx);
    const cityAccount = await tx.query<{ account_id: string }>('SELECT account_id FROM account_balances WHERE account_id = $1', [`account-city-${input.cityId}`]);
    if (!cityAccount.rows[0]) throw new Error('City credit account not found');
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT') ON CONFLICT (account_id) DO NOTHING", [`account-budget-${budgetId}`, budgetId]);
    if (deltaCents > 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: cityAccount.rows[0].account_id, creditAccount: `account-budget-${budgetId}`, amount: delta, reasonType: 'city_budget_allocation', reasonId: budgetId, ruleVersion: 'city-finance-v2', correlationId: input.correlationId });
    if (deltaCents < 0n) await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: `account-budget-${budgetId}`, creditAccount: cityAccount.rows[0].account_id, amount: delta, reasonType: 'city_budget_release', reasonId: budgetId, ruleVersion: 'city-finance-v2', correlationId: input.correlationId });
    const target = centsToMoney(targetCents);
    if (deltaCents !== 0n) await tx.query('UPDATE cities SET treasury = treasury - $1 WHERE id = $2', [deltaCents > 0n ? delta : `-${delta}`, input.cityId]);
    await tx.query('INSERT INTO budgets (id,institution_id,category,amount,game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET amount = excluded.amount, game_day = excluded.game_day', [budgetId, input.cityId, input.category, target, gameDay]);
    return { ok: true, budget: (await tx.query('SELECT * FROM budgets WHERE id = $1', [budgetId])).rows[0], city: (await tx.query('SELECT id, treasury FROM cities WHERE id = $1', [input.cityId])).rows[0], correlationId: input.correlationId };
  });
}

export async function spendCorporationTreasury(repository: PostgresRepository, input: { humanId: string; corporationId: string; cityId: string; category: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.corporationId, ['Corporation Executive', 'Corporation Treasurer']))) throw new Error('An active Corporation Executive or Treasurer term is required');
    const [corporation, city, prior] = await Promise.all([
      tx.query<{ treasury: string }>('SELECT treasury FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]),
      tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]),
      tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'corporation_public_spending' AND correlation_id = $1", [input.correlationId]),
    ]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: Number(prior.rows[0].game_day), correlationId: input.correlationId };
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!corporation.rows[0] || !city.rows[0]) throw new Error('Corporation or destination City not found');
    if (moneyToCents(corporation.rows[0].treasury) < amountCents) throw new Error('Insufficient Corporation Treasury');
    const gameDay = await day(tx);
    const [corporationAccount, cityAccount] = await Promise.all([
      tx.query<{ account_id: string }>('SELECT account_id FROM account_balances WHERE account_id = $1', [`account-corporation-${input.corporationId}`]),
      tx.query<{ account_id: string }>('SELECT account_id FROM account_balances WHERE account_id = $1', [`account-city-${input.cityId}`]),
    ]);
    if (!corporationAccount.rows[0] || !cityAccount.rows[0]) throw new Error('Institution credit account not found');
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: corporationAccount.rows[0].account_id, creditAccount: cityAccount.rows[0].account_id, amount, reasonType: 'corporation_public_spending', reasonId: input.cityId, ruleVersion: 'corp-finance-v2', correlationId: input.correlationId });
    await tx.query('UPDATE corporations SET treasury = treasury - $1 WHERE id = $2', [amount, input.corporationId]);
    await tx.query('UPDATE cities SET treasury = treasury + $1 WHERE id = $2', [amount, input.cityId]);
    await tx.query('INSERT INTO budgets (id,institution_id,category,amount,game_day) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(id) DO UPDATE SET amount = budgets.amount + excluded.amount, game_day = excluded.game_day', [`CORP-SPEND-${input.correlationId}`, input.cityId, input.category, amount, gameDay]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation_public_spending', `Corporation funding reached ${input.cityId}`, JSON.stringify({ corporationId: input.corporationId, cityId: input.cityId, category: input.category, amount, correlationId: input.correlationId })]);
    return { ok: true, amount: Number(amount), category: input.category, cityId: input.cityId, corporation: (await tx.query('SELECT id, treasury FROM corporations WHERE id = $1', [input.corporationId])).rows[0], city: (await tx.query('SELECT id, treasury FROM cities WHERE id = $1', [input.cityId])).rows[0], correlationId: input.correlationId };
  });
}

export async function contributeToCorporation(repository: PostgresRepository, input: { humanId: string; corporationId: string; amount: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const membership = await tx.query('SELECT human_id FROM memberships WHERE human_id = $1 AND corporation_id = $2', [input.humanId, input.corporationId]);
    if (!membership.rows[0]) throw new Error('Corporation membership is required');
    const prior = await tx.query<{ amount: string; game_day: number }>("SELECT amount, game_day FROM ledger_entries WHERE reason_type = 'corporation_contribution' AND correlation_id = $1", [input.correlationId]);
    if (prior.rows[0]) return { ok: true, alreadyProcessed: true, amount: Number(prior.rows[0].amount), gameDay: Number(prior.rows[0].game_day), correlationId: input.correlationId };
    const [account, corporation] = await Promise.all([
      tx.query<{ account_id: string; balance: string }>("SELECT account_id, balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT' FOR UPDATE", [input.humanId]),
      tx.query('SELECT id FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]),
    ]);
    const amountCents = moneyToCents(input.amount);
    const amount = centsToMoney(amountCents);
    if (!account.rows[0] || !corporation.rows[0]) throw new Error('Contributor or corporation account not found');
    if (moneyToCents(account.rows[0].balance) < amountCents) throw new Error('Insufficient Credits for contribution');
    const corporationAccount = await tx.query<{ account_id: string }>('SELECT account_id FROM account_balances WHERE account_id = $1', [`account-corporation-${input.corporationId}`]);
    if (!corporationAccount.rows[0]) throw new Error('Corporation credit account not found');
    const gameDay = await day(tx);
    await transferCredits(tx, { ledgerId: crypto.randomUUID(), gameDay, debitAccount: account.rows[0].account_id, creditAccount: corporationAccount.rows[0].account_id, amount, reasonType: 'corporation_contribution', reasonId: input.corporationId, ruleVersion: 'corp-finance-v2', correlationId: input.correlationId });
    await tx.query('UPDATE corporations SET treasury = treasury + $1 WHERE id = $2', [amount, input.corporationId]);
    return { ok: true, amount: Number(amount), corporation: (await tx.query('SELECT id, treasury FROM corporations WHERE id = $1', [input.corporationId])).rows[0], correlationId: input.correlationId };
  });
}
