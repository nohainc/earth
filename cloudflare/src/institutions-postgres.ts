import type { PostgresRepository } from './repository.ts';
import { transferCredits } from './financial-postgres.ts';
import { centsToMoney, moneyToCents } from './money.ts';
import { fromNanoMarkup, toNanoMarkup } from './nano-markup.ts';

async function day(repository: PostgresRepository): Promise<number> {
  const result = await repository.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
  return Number(result.rows[0]?.game_day ?? 0);
}

async function uniqueInstitutionName(repository: PostgresRepository, name: string): Promise<void> {
  const result = await repository.query('SELECT id FROM institutions WHERE lower(name) = lower($1) UNION ALL SELECT id FROM communities WHERE lower(name) = lower($1) LIMIT 1', [name]);
  if (result.rows[0]) throw new Error('Institution name already exists');
}

export async function listCities(repository: PostgresRepository): Promise<Record<string, unknown>> {
  return {
    cities: (await repository.query(`SELECT cities.*, corporation_institutions.name AS corporation_name
      FROM cities
      LEFT JOIN institutions corporation_institutions ON corporation_institutions.id = cities.corporation_id
      ORDER BY cities.id`)).rows,
  };
}

export async function listCorporations(repository: PostgresRepository, search = ''): Promise<Record<string, unknown>> {
  const term = `%${search.trim().replace(/[%_]/g, '')}%`;
  const result = await repository.query(`
    SELECT corporations.*, institutions.name, institutions.status,
           capital_institutions.name AS capital_city_name,
           institutions.charter_rules,
           COALESCE((SELECT COUNT(*) FROM cities WHERE cities.corporation_id = corporations.id), 0)::integer AS city_count
    FROM corporations
    JOIN institutions ON institutions.id = corporations.institution_id
    LEFT JOIN institutions capital_institutions ON capital_institutions.id = corporations.capital_city_id
    WHERE institutions.status = 'active' AND ($1 = '%%' OR institutions.name ILIKE $1)
    ORDER BY corporations.member_count DESC, institutions.name ASC
    LIMIT 100`, [term]);
  return {
    corporations: result.rows.map((row) => ({
      ...row,
      rules: fromNanoMarkup<Record<string, unknown>>(row.charter_rules),
      charter_rules: undefined,
    })),
  };
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
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'city.formed', `${name} was founded`, toNanoMarkup({ cityId, communityId: input.communityId, residents })]);
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
    await tx.query("INSERT INTO corporations (id,institution_id,member_count,treasury,constitution_version,capital_city_id,admission_policy) VALUES ($1,$1,0,0,1,$2,'open')", [corporationId, input.cityId]);
    await tx.query('UPDATE cities SET corporation_id = $1 WHERE id = $2', [corporationId, input.cityId]);
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1, $2, 0, 'CREDIT')", [`account-corporation-${corporationId}`, corporationId]);
    await tx.query("INSERT INTO institution_roles (id,institution_id,name,term_days,eligibility) VALUES ($1,$2,'Corporation Executive',90,'member'),($3,$2,'Corporation Treasurer',90,'member'),($4,$2,'OUC Delegate',90,'representative')", [`${corporationId}-EXECUTIVE`, corporationId, `${corporationId}-TREASURER`, `${corporationId}-DELEGATE`]);
    await tx.query("INSERT INTO role_assignments (id,role_id,institution_id,human_id,started_game_day,ends_game_day) VALUES ($1,$2,$3,$4,$5,$6)", [crypto.randomUUID(), `${corporationId}-EXECUTIVE`, corporationId, input.founderId, gameDay, gameDay + 90]);
    await tx.query('UPDATE memberships SET corporation_id = $1 WHERE city_id = $2 AND corporation_id IS NULL', [corporationId, input.cityId]);
    await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [corporationId]);
    for (const member of members.rows) {
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'corporation_formation')", [crypto.randomUUID(), member.human_id, corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6)', [`CORP-FORMED-${member.human_id}-${corporationId}`, member.human_id, 'institution', 'Corporation formed', `Corporation ${corporationId} was formed and you became a member.`, corporationId]);
    }
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation.formed', `${name} was formed`, toNanoMarkup({ corporationId, cityId: input.cityId, members: Number(city.rows[0].residents) })]);
    return { ok: true, corporation: (await tx.query('SELECT * FROM corporations WHERE id = $1', [corporationId])).rows[0] };
  });
}

export async function createCorporationWithCapital(repository: PostgresRepository, input: { founderId: string; corporationName: string; cityName: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const corporationName = input.corporationName.trim();
    const cityName = input.cityName.trim();
    if (corporationName.length < 2 || corporationName.length > 80 || cityName.length < 2 || cityName.length > 80) {
      throw new Error('Corporation and capital city names must be 2 to 80 characters');
    }
    const founder = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.founderId]);
    const existingMembership = await tx.query<{ corporation_id: string | null }>('SELECT corporation_id FROM memberships WHERE human_id = $1', [input.founderId]);
    if (!founder.rows[0]) throw new Error('Human not found');
    if (existingMembership.rows[0]?.corporation_id) throw new Error('Leave your current corporation before founding another one');
    await uniqueInstitutionName(tx, corporationName);
    await uniqueInstitutionName(tx, cityName);
    const cityId = `CITY-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const corporationId = `CORP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const gameDay = await day(tx);
    await tx.query("INSERT INTO institutions (id,kind,name,status) VALUES ($1,'CITY',$2,'active'),($3,'CORPORATION',$4,'active')", [cityId, cityName, corporationId, corporationName]);
    // The city and corporation reference each other. Insert the city first
    // without the corporation foreign-key, then attach it after the
    // corporation row exists.
    await tx.query('INSERT INTO cities (id,institution_id,residents,housing_capacity,energy_capacity,connectivity_capacity,health_capacity,treasury) VALUES ($1,$1,1,10,10,10,50,0)', [cityId]);
    await tx.query("INSERT INTO corporations (id,institution_id,member_count,treasury,constitution_version,capital_city_id,admission_policy) VALUES ($1,$1,1,0,1,$2,'open')", [corporationId, cityId]);
    await tx.query('UPDATE cities SET corporation_id = $1 WHERE id = $2', [corporationId, cityId]);
    await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = excluded.city_id, joined_game_day = excluded.joined_game_day', [input.founderId, corporationId, cityId, gameDay]);
    await tx.query("INSERT INTO account_balances (account_id, owner_id, balance, currency) VALUES ($1,$2,0,'CREDIT'),($3,$4,0,'CREDIT')", [`account-city-${cityId}`, cityId, `account-corporation-${corporationId}`, corporationId]);
    await tx.query("INSERT INTO institution_roles (id,institution_id,name,term_days,eligibility) VALUES ($1,$2,'City Mayor',90,'resident'),($3,$2,'Infrastructure Planner',90,'resident'),($4,$5,'Corporation Executive',90,'member'),($6,$5,'Corporation Treasurer',90,'member')", [`${cityId}-MAYOR`, cityId, `${cityId}-PLANNER`, `${corporationId}-EXECUTIVE`, corporationId, `${corporationId}-TREASURER`]);
    await tx.query("INSERT INTO role_assignments (id,role_id,institution_id,human_id,started_game_day,ends_game_day) VALUES ($1,$2,$3,$4,$5,$6),($7,$8,$9,$4,$5,$6)", [crypto.randomUUID(), `${cityId}-MAYOR`, cityId, input.founderId, gameDay, gameDay + 90, crypto.randomUUID(), `${corporationId}-EXECUTIVE`, corporationId]);
    await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CITY',$3,'joined',$4,'corporation_founding'),($5,$2,'CORPORATION',$6,'joined',$4,'corporation_founding')", [crypto.randomUUID(), input.founderId, cityId, gameDay, crypto.randomUUID(), corporationId]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation.founded', `${corporationName} was founded`, toNanoMarkup({ corporationId, cityId, founderId: input.founderId })]);
    return { ok: true, corporation: (await tx.query('SELECT * FROM corporations WHERE id = $1', [corporationId])).rows[0], capitalCity: (await tx.query('SELECT * FROM cities WHERE id = $1', [cityId])).rows[0] };
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

export async function adoptCityForCorporation(repository: PostgresRepository, input: { humanId: string; corporationId: string; cityId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.corporationId, ['Corporation Executive']))) {
      throw new Error('An active Corporation Executive term is required');
    }
    const corporation = await tx.query<{ id: string }>('SELECT id FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]);
    const city = await tx.query<{ id: string; corporation_id: string | null; admission_policy: string | null }>(
      'SELECT cities.id, cities.corporation_id, corporations.admission_policy FROM cities LEFT JOIN corporations ON corporations.id = cities.corporation_id WHERE cities.id = $1 FOR UPDATE OF cities',
      [input.cityId],
    );
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    if (!city.rows[0]) throw new Error('City not found');
    if (city.rows[0].corporation_id && city.rows[0].corporation_id !== input.corporationId) {
      throw new Error('City already belongs to another corporation');
    }
    const conflicting = await tx.query<{ human_id: string }>('SELECT human_id FROM memberships WHERE city_id = $1 AND corporation_id IS NOT NULL AND corporation_id <> $2 LIMIT 1', [input.cityId, input.corporationId]);
    if (conflicting.rows[0]) throw new Error('City residents include members of another corporation');
    const gameDay = await day(tx);
    await tx.query('UPDATE cities SET corporation_id = $1 WHERE id = $2', [input.corporationId, input.cityId]);
    await tx.query('UPDATE memberships SET corporation_id = $1 WHERE city_id = $2 AND corporation_id IS NULL', [input.corporationId, input.cityId]);
    await refreshPopulation(tx, input.corporationId, [input.cityId]);
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation.city_adopted', `Corporation ${input.corporationId} adopted city ${input.cityId}`, toNanoMarkup({ corporationId: input.corporationId, cityId: input.cityId, humanId: input.humanId })]);
    return { ok: true, corporationId: input.corporationId, cityId: input.cityId, membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null };
  });
}

async function refreshPopulation(tx: PostgresRepository, corporationId: string | null, cityIds: Array<string | null>): Promise<void> {
  if (corporationId) await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [corporationId]);
  for (const cityId of [...new Set(cityIds.filter((value): value is string => Boolean(value)))]) {
    await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [cityId]);
  }
}

export async function changeCorporationMembership(repository: PostgresRepository, input: { humanId: string; corporationId: string; action: 'join' | 'leave' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const corporation = await tx.query<{ id: string; capital_city_id: string | null; admission_policy: string }>('SELECT id, capital_city_id, admission_policy FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]);
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query<{ corporation_id: string | null; city_id: string | null }>('SELECT corporation_id, city_id FROM memberships WHERE human_id = $1 FOR UPDATE', [input.humanId]);
    const current = existing.rows[0] ?? { corporation_id: null, city_id: null };
    const gameDay = await day(tx);
    if (input.action === 'leave') {
      if (current.corporation_id !== input.corporationId) throw new Error('Human is not a member of this corporation');
      // City affiliation is part of corporation membership. Leaving the
      // corporation therefore returns the person to the independent state.
      await tx.query('UPDATE memberships SET corporation_id = NULL, city_id = NULL WHERE human_id = $1 AND corporation_id = $2', [input.humanId, input.corporationId]);
      await refreshPopulation(tx, input.corporationId, [current.city_id]);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'left',$4,'voluntary_resignation')", [crypto.randomUUID(), input.humanId, input.corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING', [`CORP-LEFT-${input.humanId}-${input.corporationId}-${gameDay}`, input.humanId, 'institution', 'Corporation left', `You left corporation ${input.corporationId}.`, input.corporationId]);
    } else {
      // Do not clear the current membership until an approval-based join has
      // actually been accepted. A pending request must leave the member in
      // their current corporation.
      if (corporation.rows[0].admission_policy === 'approval') {
        const existingRequest = await tx.query<{ id: string }>("SELECT id FROM corporation_membership_requests WHERE corporation_id = $1 AND human_id = $2 AND status = 'pending'", [input.corporationId, input.humanId]);
        if (existingRequest.rows[0]) return { ok: true, membership: current, requestStatus: 'pending' };
        await tx.query("INSERT INTO corporation_membership_requests (id, corporation_id, human_id, status, requested_game_day) VALUES ($1,$2,$3,'pending',$4)", [crypto.randomUUID(), input.corporationId, input.humanId, gameDay]);
        return { ok: true, membership: current, requestStatus: 'pending' };
      }
      if (current.corporation_id && current.corporation_id !== input.corporationId) {
        // Cleanly transfer from previous corporation
        await tx.query('UPDATE memberships SET corporation_id = NULL, city_id = NULL WHERE human_id = $1', [input.humanId]);
        await refreshPopulation(tx, current.corporation_id, [current.city_id]);
        await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'left',$4,'corporation_transfer')", [crypto.randomUUID(), input.humanId, current.corporation_id, gameDay]);
      }
      let cityId = corporation.rows[0].capital_city_id;
      if (!cityId) {
        const cityRes = await tx.query<{ id: string }>('SELECT id FROM cities WHERE corporation_id = $1 LIMIT 1', [input.corporationId]);
        cityId = cityRes.rows[0]?.id ?? null;
      }
      if (!cityId) {
        const defaultCityRes = await tx.query<{ id: string }>('SELECT id FROM cities LIMIT 1');
        cityId = defaultCityRes.rows[0]?.id ?? 'CITY-0084';
      }
      await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = excluded.city_id, joined_game_day = excluded.joined_game_day', [input.humanId, input.corporationId, cityId, gameDay]);
      await refreshPopulation(tx, input.corporationId, [current.city_id, cityId]);
      if (current.city_id && current.city_id !== cityId) await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CITY',$3,'left',$4,'corporation_affiliation')", [crypto.randomUUID(), input.humanId, current.city_id, gameDay]);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'voluntary_membership')", [crypto.randomUUID(), input.humanId, input.corporationId, gameDay]);
      await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING', [`CORP-JOINED-${input.humanId}-${input.corporationId}-${gameDay}`, input.humanId, 'institution', 'Corporation joined', `You joined corporation ${input.corporationId}.`, input.corporationId]);
    }
    return { ok: true, membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null };
  });
}

export async function setCorporationAdmissionPolicy(repository: PostgresRepository, input: { humanId: string; corporationId: string; policy: 'open' | 'approval' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.corporationId, ['Corporation Executive']))) {
      throw new Error('An active Corporation Executive term is required');
    }
    const result = await tx.query('UPDATE corporations SET admission_policy = $1 WHERE id = $2 RETURNING id, admission_policy', [input.policy, input.corporationId]);
    if (!result.rows[0]) throw new Error('Corporation not found');
    return { ok: true, corporation: result.rows[0] };
  });
}

export async function decideCorporationMembershipRequest(repository: PostgresRepository, input: { humanId: string; corporationId: string; requestId: string; decision: 'approved' | 'rejected' }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.corporationId, ['Corporation Executive']))) {
      throw new Error('An active Corporation Executive term is required');
    }
    const corporation = await tx.query<{ capital_city_id: string | null }>('SELECT capital_city_id FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]);
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const request = await tx.query<{ id: string; human_id: string }>("SELECT id, human_id FROM corporation_membership_requests WHERE id = $1 AND corporation_id = $2 AND status = 'pending' FOR UPDATE", [input.requestId, input.corporationId]);
    if (!request.rows[0]) throw new Error('Pending membership request not found');
    const gameDay = await day(tx);
    await tx.query('UPDATE corporation_membership_requests SET status = $1, decided_game_day = $2, decided_by = $3 WHERE id = $4', [input.decision, gameDay, input.humanId, input.requestId]);
    if (input.decision === 'approved') {
      if (!corporation.rows[0].capital_city_id) throw new Error('Corporation has no capital city');
      await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = excluded.corporation_id, city_id = excluded.city_id, joined_game_day = excluded.joined_game_day', [request.rows[0].human_id, input.corporationId, corporation.rows[0].capital_city_id, gameDay]);
      await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [input.corporationId]);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'membership_request_approved')", [crypto.randomUUID(), request.rows[0].human_id, input.corporationId, gameDay]);
    }
    await tx.query('INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING', [`CORP-REQUEST-${input.requestId}-${input.decision}`, request.rows[0].human_id, 'institution', `Corporation request ${input.decision}`, `Your membership request was ${input.decision}.`, input.corporationId]);
    return { ok: true, request: (await tx.query('SELECT * FROM corporation_membership_requests WHERE id = $1', [input.requestId])).rows[0] };
  });
}

export async function changeCityResidency(repository: PostgresRepository, input: { humanId: string; cityId: string; action: 'join' | 'leave'; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const city = await tx.query<{ id: string; corporation_id: string | null }>('SELECT id, corporation_id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const replay = await tx.query<{ action: string; game_day: number }>('SELECT action, game_day FROM membership_events WHERE id = $1 AND human_id = $2 AND institution_id = $3', [input.correlationId, input.humanId, input.cityId]);
    if (replay.rows[0]) return { ok: true, alreadyProcessed: true, residency: replay.rows[0].action === 'joined' ? 'resident' : 'independent', correlationId: input.correlationId, gameDay: Number(replay.rows[0].game_day), membership: (await tx.query('SELECT * FROM memberships WHERE human_id = $1', [input.humanId])).rows[0] ?? null };
    const human = await tx.query<{ id: string }>("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [input.humanId]);
    if (!human.rows[0]) throw new Error('Human not found');
    const existing = await tx.query<{ city_id: string | null; corporation_id: string | null }>('SELECT city_id, corporation_id FROM memberships WHERE human_id = $1 FOR UPDATE', [input.humanId]);
    const previousCityId = existing.rows[0]?.city_id ?? null;
    const cityCorporationId = city.rows[0]?.corporation_id ?? null;
    if (input.action === 'join' && existing.rows[0]?.corporation_id && existing.rows[0].corporation_id !== cityCorporationId) {
      throw new Error(cityCorporationId ? 'This city belongs to another corporation' : 'Corporation members may move only to a city in their corporation network');
    }
    if (input.action === 'join' && cityCorporationId && !existing.rows[0]?.corporation_id && city.rows[0]?.admission_policy === 'approval') {
      throw new Error('This city follows its parent corporation approval policy. Apply to the corporation before establishing residency.');
    }
    const gameDay = await day(tx);
    if (input.action === 'join') {
      await tx.query('INSERT INTO memberships (human_id, corporation_id, city_id, joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = COALESCE(memberships.corporation_id, excluded.corporation_id), city_id = excluded.city_id, joined_game_day = excluded.joined_game_day', [input.humanId, existing.rows[0]?.corporation_id ?? cityCorporationId, input.cityId, gameDay]);
      if (previousCityId && previousCityId !== input.cityId) {
        await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CITY',$3,'left',$4,'city_transfer')", [crypto.randomUUID(), input.humanId, previousCityId, gameDay]);
      }
    } else {
      await tx.query('UPDATE memberships SET city_id = NULL WHERE human_id = $1 AND city_id = $2', [input.humanId, input.cityId]);
    }
    await refreshPopulation(tx, null, [previousCityId, input.cityId]);
    if (input.action === 'join' && cityCorporationId && !existing.rows[0]?.corporation_id) {
      await refreshPopulation(tx, cityCorporationId, []);
      await tx.query("INSERT INTO membership_events (id,human_id,institution_type,institution_id,action,game_day,reason) VALUES ($1,$2,'CORPORATION',$3,'joined',$4,'city_affiliation')", [crypto.randomUUID(), input.humanId, cityCorporationId, gameDay]);
    }
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
    await tx.query('INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation_public_spending', `Corporation funding reached ${input.cityId}`, toNanoMarkup({ corporationId: input.corporationId, cityId: input.cityId, category: input.category, amount, correlationId: input.correlationId })]);
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

export async function setCityTaxCharter(repository: PostgresRepository, input: { humanId: string; cityId: string; incomeTaxBps: number; salesTaxBps: number; corporateTaxBps: number; propertyTaxBps: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.cityId, ['City Mayor', 'Infrastructure Planner']))) {
      throw new Error('An active City Mayor or Infrastructure Planner term is required');
    }
    const city = await tx.query<{ id: string }>('SELECT id FROM cities WHERE id = $1 FOR UPDATE', [input.cityId]);
    if (!city.rows[0]) throw new Error('City not found');
    const incomeBps = Math.max(0, Math.min(5000, Math.round(Number(input.incomeTaxBps ?? 0))));
    const salesBps = Math.max(0, Math.min(2500, Math.round(Number(input.salesTaxBps ?? 0))));
    const corporateBps = Math.max(0, Math.min(5000, Math.round(Number(input.corporateTaxBps ?? 0))));
    const propertyBps = Math.max(0, Math.min(3000, Math.round(Number(input.propertyTaxBps ?? 0))));
    const gameDay = await day(tx);
    const charter = {
      incomeTaxBps: incomeBps,
      salesTaxBps: salesBps,
      corporateTaxBps: corporateBps,
      propertyTaxBps: propertyBps,
      updatedBy: input.humanId,
      updatedGameDay: gameDay,
    };
    await tx.query('UPDATE institutions SET charter_rules = $1 WHERE id = $2', [toNanoMarkup(charter), input.cityId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'city.tax_charter_updated', `Municipal Tax Charter updated for ${input.cityId}`, toNanoMarkup({ cityId: input.cityId, charter, correlationId: input.correlationId })]);
    return { ok: true, cityId: input.cityId, charter, correlationId: input.correlationId };
  });
}

export async function setCorporationTaxCharter(repository: PostgresRepository, input: { humanId: string; corporationId: string; incomeTaxBps: number; salesTaxBps: number; corporateTaxBps: number; propertyTaxBps: number; correlationId: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if (!(await hasRole(tx, input.humanId, input.corporationId, ['Corporation Executive', 'Corporation Treasurer']))) {
      throw new Error('An active Corporation Executive or Corporation Treasurer term is required');
    }
    const corporation = await tx.query<{ id: string }>('SELECT id FROM corporations WHERE id = $1 FOR UPDATE', [input.corporationId]);
    if (!corporation.rows[0]) throw new Error('Corporation not found');
    const incomeTaxBps = Math.max(0, Math.min(5000, Math.round(Number(input.incomeTaxBps ?? 0))));
    const salesTaxBps = Math.max(0, Math.min(2500, Math.round(Number(input.salesTaxBps ?? 0))));
    const corporateTaxBps = Math.max(0, Math.min(5000, Math.round(Number(input.corporateTaxBps ?? 0))));
    const propertyTaxBps = Math.max(0, Math.min(3000, Math.round(Number(input.propertyTaxBps ?? 0))));
    const gameDay = await day(tx);
    const charter = { incomeTaxBps, salesTaxBps, corporateTaxBps, propertyTaxBps, updatedBy: input.humanId, updatedGameDay: gameDay };
    await tx.query('UPDATE institutions SET charter_rules = $1 WHERE id = $2', [toNanoMarkup(charter), input.corporationId]);
    await tx.query('INSERT INTO world_events (id, game_day, event_type, title, details) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), gameDay, 'corporation.tax_charter_updated', `Corporation Tax Charter updated for ${input.corporationId}`, toNanoMarkup({ corporationId: input.corporationId, charter, correlationId: input.correlationId })]);
    return { ok: true, corporationId: input.corporationId, charter, correlationId: input.correlationId };
  });
}
