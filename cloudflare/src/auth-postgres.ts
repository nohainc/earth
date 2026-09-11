import type { PostgresRepository } from './repository';
import { calculateStarterPackage, economicStartIndex } from './starter-package.ts';
import {
  base64ToBytes,
  bytesToBase64,
  derivePassword,
  digest,
  SESSION_DAYS,
} from './auth-crypto.ts';
import { enqueueOutbox } from './outbox-postgres.ts';

export async function registerIdentity(repository: PostgresRepository, input: { email: string; personName: string; houseSurname: string; password: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const existing = await tx.query('SELECT id FROM auth_accounts WHERE email = $1', [input.email]);
    if (existing.rows[0]) throw new Error('Email is already registered');
    const world = await tx.query<{ game_day: number; living_cost_index: string }>("SELECT game_day, living_cost_index FROM world_state WHERE id = 'WORLD'");
    const referencePrice = await tx.query<{ reference_price: string }>("SELECT COALESCE(AVG(price), 50) AS reference_price FROM market_prices WHERE product IN ('components', 'energy')");
    const worldDay = Number(world.rows[0]?.game_day ?? 184);
    const starter = calculateStarterPackage(world.rows[0]?.living_cost_index ?? 1, economicStartIndex(referencePrice.rows[0]?.reference_price ?? 50));
    const humanId = `H-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const accountId = `account-${humanId.toLowerCase()}`;
    const houseId = `HOUSE-${humanId.slice(2)}`;
    const displayName = `${input.personName} ${input.houseSurname}`;
    const houseName = `House ${input.houseSurname}`;
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const iterations = 100000;
    const passwordHash = await derivePassword(input.password, salt, iterations);
    // The humans INSERT fires daily profile provisioning. Register the
    // canonical owner before that trigger creates the settlement profile.
    await tx.query("INSERT INTO owner_registry (id, owner_type, source_id) VALUES ($1, 'human', $1)", [humanId]);
    await tx.query("UPDATE houses SET email = 'deleted-' || id || '-' || email, account_id = 'deleted-' || id || '-' || account_id WHERE email = $1", [input.email]);
    await tx.query("INSERT INTO houses (id,account_id,email,house_name,motto,founder_human_id,legacy_points,dynasty_legacy,generation,status) VALUES ($1,$2,$3,$4,$5,NULL,0,0,1,'ACTIVE')", [houseId, input.email, input.email, houseName, 'From the Red Dust We Build Eternity']);
    await tx.query('INSERT INTO humans (id,account_id,house_id,display_name,age_years,standing,legacy,political_eligibility_game_day) VALUES ($1,$2,$3,$4,31,0,0,$5)', [humanId, accountId, houseId, displayName, worldDay + 30]);
    await tx.query('INSERT INTO auth_accounts (id,house_id,email,password_hash,password_salt,password_iterations) VALUES ($1,$2,$3,$4,$5,$6)', [`AUTH-${houseId}`, houseId, input.email, passwordHash, bytesToBase64(salt), iterations]);
    await tx.query(
      `INSERT INTO buildings (
         id, city_id, owner_id, catalog_id, building_type, name, tier,
         slot_footprint, ownership_class, operating_policy,
         upkeep_energy, upkeep_food, upkeep_materials, upkeep_components,
         upkeep_compute, daily_operating_credits, resource_output_type,
         resource_output_amount, construction_started_game_day,
         construction_complete_game_day, construction_progress, status, created_game_day
       )
       SELECT 'BLD-ESTATE-' || $1, NULL, $1, c.id, c.building_type, c.name,
              c.tier, c.slot_footprint, c.ownership_class, 'balanced',
              c.upkeep_energy, c.upkeep_food, c.upkeep_materials,
              c.upkeep_components, c.upkeep_compute, c.operating_credits,
              NULL, 0, $2, $2, 100, 'active', $2
       FROM building_catalog c
       WHERE c.id = 'private-estate-plot-t1'
       ON CONFLICT (id) DO NOTHING`,
      [humanId, worldDay],
    );
    await tx.query('INSERT INTO auth_credentials (human_id,email,password_hash,password_salt,password_iterations) VALUES ($1,$2,$3,$4,$5)', [humanId, input.email, passwordHash, bytesToBase64(salt), iterations]);
    await tx.query("INSERT INTO account_balances (account_id,owner_id,balance,currency) VALUES ($1,$2,$3,'CREDIT')", [accountId, humanId, starter.credits]);
    for (const [resource, amount] of Object.entries(starter.resources)) await tx.query('INSERT INTO resource_balances (owner_id,resource,amount) VALUES ($1,$2,$3)', [humanId, resource, amount]);
    await tx.query('UPDATE houses SET founder_human_id = $1, current_human_id = $1 WHERE id = $2', [humanId, houseId]);
    await tx.query("INSERT INTO house_lineage_records (id,house_id,human_id,generation,name,title,birth_game_day,is_incumbent,legacy_score) VALUES ($1,$2,$3,1,$4,'House Founder',$5,true,0)", [crypto.randomUUID(), houseId, humanId, displayName, worldDay]);
    await tx.query("INSERT INTO personal_financial_states (human_id, status, since_game_day, protected_credits, last_reason) VALUES ($1, 'active', $2, 100, 'starter-package')", [humanId, worldDay]);
    await enqueueOutbox(tx, {
      eventKey: `starter-package:${humanId}`,
      topic: 'world_activity',
      aggregateType: 'human',
      aggregateId: humanId,
      payload: { type: 'world_activity', category: 'identity', action: 'starter_package_created', humanId, gameDay: worldDay },
    });
    return { ok: true, human: { id: humanId, displayName, personName: input.personName, houseSurname: input.houseSurname, houseName, email: input.email }, starterPackage: starter };
  });
}

export async function updateDisplayName(repository: PostgresRepository, input: { humanId: string; displayName?: string; epitaph?: string }): Promise<Record<string, unknown>> {
  if (input.displayName) {
    await repository.query('UPDATE humans SET display_name = $1 WHERE id = $2', [input.displayName, input.humanId]);
    await repository.query('UPDATE house_lineage_records SET name = $1 WHERE human_id = $2 AND is_incumbent = true', [input.displayName, input.humanId]);
  }
  if (input.epitaph !== undefined) {
    await repository.query('UPDATE house_lineage_records SET epitaph = $1 WHERE human_id = $2', [input.epitaph, input.humanId]);
    await repository.query('UPDATE deceased_profiles SET epitaph = $1 WHERE human_id = $2', [input.epitaph, input.humanId]);
  }
  const result = await repository.query<{ id: string; display_name: string }>('SELECT id, display_name FROM humans WHERE id = $1', [input.humanId]);
  if (!result.rows[0]) throw new Error('Human not found');
  return { ok: true, human: result.rows[0], epitaph: input.epitaph };
}

export async function loginIdentity(repository: PostgresRepository, input: { email: string; password: string; otp: string; validTotp: (secret: string, code: string) => Promise<boolean> }): Promise<Record<string, unknown>> {
  const attempt = (await repository.query<{ window_started_at: string; attempt_count: number; blocked_until: string | null }>('SELECT window_started_at, attempt_count, blocked_until FROM auth_login_attempts WHERE email = $1', [input.email])).rows[0];
  if (attempt?.blocked_until && new Date(attempt.blocked_until).getTime() > Date.now()) throw new Error('Too many login attempts. Try again later.');
    const credential = (await repository.query<{ account_id: string; house_id: string; password_hash: string; password_salt: string; password_iterations: number; email_verified_at: string | null; mfa_enabled: boolean; mfa_secret: string | null; life_status: string }>("SELECT auth_accounts.id AS account_id, auth_accounts.house_id, auth_accounts.*, humans.life_status FROM auth_accounts JOIN houses ON houses.id = auth_accounts.house_id JOIN humans ON humans.id = houses.current_human_id WHERE auth_accounts.email = $1 AND houses.status = 'ACTIVE' AND humans.account_status = 'active'", [input.email])).rows[0];
  if (!credential) throw new Error('Invalid email or password');
  if (!credential.email_verified_at) throw new Error('Verify your email before signing in');
  const matches = Boolean(input.password.length && await derivePassword(input.password, base64ToBytes(credential.password_salt), Number(credential.password_iterations)) === credential.password_hash);
  if (!matches) {
    const withinWindow = Boolean(attempt && Date.now() - new Date(attempt.window_started_at).getTime() < 15 * 60 * 1000);
    const count = withinWindow ? Number(attempt?.attempt_count ?? 0) + 1 : 1;
    const blockedUntil = count >= 5 ? new Date(Date.now() + 15 * 60 * 1000).toISOString() : null;
    await repository.query('INSERT INTO auth_login_attempts (email,window_started_at,attempt_count,blocked_until) VALUES ($1,CURRENT_TIMESTAMP,$2,$3) ON CONFLICT(email) DO UPDATE SET window_started_at = CASE WHEN $4::boolean THEN auth_login_attempts.window_started_at ELSE CURRENT_TIMESTAMP END, attempt_count = $2, blocked_until = $3', [input.email, count, blockedUntil, withinWindow]);
    throw new Error('Invalid email or password');
  }
  if (credential.mfa_enabled && (!credential.mfa_secret || !(await input.validTotp(credential.mfa_secret, input.otp)))) throw new Error('Authenticator code required');
  await repository.query('DELETE FROM auth_login_attempts WHERE email = $1', [input.email]);
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
  await repository.query('INSERT INTO auth_sessions (id,account_id,human_id,token_hash,expires_at) SELECT $1,$2,h.current_human_id,$3,$4 FROM houses h WHERE h.id = $5', [crypto.randomUUID(), credential.account_id, await digest(token), expires, credential.house_id]);
  const human = (await repository.query<{ id: string; house_id: string; display_name: string; life_status: string }>('SELECT id, house_id, display_name, life_status FROM humans WHERE id = (SELECT current_human_id FROM houses WHERE id = $1)', [credential.house_id])).rows[0];
  return { ok: true, human, lifeStatus: human?.life_status ?? credential.life_status, expiresAt: expires, token, maxAge: SESSION_DAYS * 86400 };
}

export async function rebornIdentity(repository: PostgresRepository, input: { email: string; displayName: string; dynastyName?: string; startingCityId?: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const cred = (await tx.query<{ account_id: string; house_id: string; human_id: string; email: string }>(`SELECT a.id AS account_id, a.house_id, a.email,
      COALESCE(h.current_human_id, (SELECT l.human_id FROM house_lineage_records l WHERE l.house_id = a.house_id ORDER BY l.generation DESC, l.created_at DESC LIMIT 1)) AS human_id
      FROM auth_accounts a JOIN houses h ON h.id = a.house_id WHERE a.email = $1`, [input.email])).rows[0];
    if (!cred) throw new Error('Account not found');
    const prevHuman = (await tx.query<{ id: string; display_name: string; legacy: number; standing: number; life_status: string }>('SELECT id, display_name, legacy, standing, life_status FROM humans WHERE id = $1', [cred.human_id])).rows[0];
    if (!prevHuman || !['deceased', 'estate'].includes(prevHuman.life_status)) {
      throw new Error('Civic Rebirth is available only after mortality or during an estate period');
    }
    const existingHouse = (await tx.query<{ id: string; house_name: string }>('SELECT id, house_name FROM houses WHERE account_id = $1 OR email = $1', [input.email])).rows[0];

    const world = await tx.query<{ game_day: number; living_cost_index: string }>("SELECT game_day, living_cost_index FROM world_state WHERE id = 'WORLD'");
    const worldDay = Number(world.rows[0]?.game_day ?? 184);
    const referencePrice = await tx.query<{ reference_price: string }>("SELECT COALESCE(AVG(price), 50) AS reference_price FROM market_prices WHERE product IN ('components', 'energy')");
    const starter = calculateStarterPackage(world.rows[0]?.living_cost_index ?? 1, economicStartIndex(referencePrice.rows[0]?.reference_price ?? 50));

    const newHumanId = `H-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const newAccountId = `account-${newHumanId.toLowerCase()}`;
    const cityId = input.startingCityId ?? 'CITY-0084';
    const city = (await tx.query<{ id: string; corporation_id: string | null }>('SELECT id, corporation_id FROM cities WHERE id = $1', [cityId])).rows[0];
    if (!city) throw new Error(`Starting city ${cityId} does not exist`);

    // 1. Create new Human with starter capital minus 500 Credit Naturalization Fee (net 9,500 Credits)
    const netStartingCredits = Math.max(1000, Number(starter.credits) - 500);
    // The humans INSERT fires daily profile provisioning, so the canonical
    // owner must exist before the trigger creates that profile.
    await tx.query("INSERT INTO owner_registry (id, owner_type, source_id) VALUES ($1, 'human', $1)", [newHumanId]);
    if (!existingHouse) throw new Error('House principal not found');
    await tx.query('INSERT INTO humans (id,account_id,house_id,display_name,age_years,standing,legacy,life_status) VALUES ($1,$2,$3,$4,20,500,$5,\'active\')', [newHumanId, newAccountId, existingHouse.id, input.displayName, Math.floor(Number(prevHuman?.legacy ?? 0) * 0.25)]);
    await tx.query(
      `INSERT INTO buildings (
         id, city_id, owner_id, catalog_id, building_type, name, tier,
         slot_footprint, ownership_class, operating_policy,
         upkeep_energy, upkeep_food, upkeep_materials, upkeep_components,
         upkeep_compute, daily_operating_credits, resource_output_type,
         resource_output_amount, construction_started_game_day,
         construction_complete_game_day, construction_progress, status, created_game_day
       )
       SELECT 'BLD-ESTATE-' || $1, NULL, $1, c.id, c.building_type, c.name,
              c.tier, c.slot_footprint, c.ownership_class, 'balanced',
              c.upkeep_energy, c.upkeep_food, c.upkeep_materials,
              c.upkeep_components, c.upkeep_compute, c.operating_credits,
              NULL, 0, $2, $2, 100, 'active', $2
       FROM building_catalog c
       WHERE c.id = 'private-estate-plot-t1'
       ON CONFLICT (id) DO NOTHING`,
      [newHumanId, worldDay],
    );
    await tx.query('INSERT INTO account_balances (account_id,owner_id,currency,balance) VALUES ($1,$2,\'CREDIT\',$3)', [newAccountId, newHumanId, netStartingCredits]);

    // 2. Distribute Naturalization Fee (250 C to UC Treasury, 250 C to City Treasury)
    await tx.query('UPDATE account_balances SET balance = balance + 250 WHERE account_id = \'account-ouc-treasury\'');
    await tx.query('UPDATE account_balances SET balance = balance + 250 WHERE account_id = $1', [`account-${cityId}-treasury`]).catch(() => tx.query('UPDATE account_balances SET balance = balance + 250 WHERE account_id = \'account-ouc-treasury\''));

    // 3. Setup resources and technology.
    await tx.query("INSERT INTO personal_financial_states (human_id,status,since_game_day,protected_credits,last_reason) VALUES ($1,'active',$2,100,'rebirth')", [newHumanId, worldDay]);
    for (const [res, amt] of Object.entries(starter.resources)) {
      await tx.query('INSERT INTO resource_balances (owner_id,resource,amount) VALUES ($1,$2,$3)', [newHumanId, res, amt]);
    }
    // Rebirth begins in the selected city and accepts its corporation rules
    // when that city is corporation-owned.
    await tx.query('INSERT INTO memberships (human_id,corporation_id,city_id,joined_game_day) VALUES ($1,$2,$3,$4) ON CONFLICT(human_id) DO UPDATE SET corporation_id = EXCLUDED.corporation_id, city_id = EXCLUDED.city_id', [newHumanId, city.corporation_id, cityId, worldDay]);
    if (city.corporation_id) {
      await tx.query('UPDATE corporations SET member_count = (SELECT COUNT(*) FROM memberships WHERE corporation_id = $1) WHERE id = $1', [city.corporation_id]);
      await tx.query('UPDATE cities SET residents = (SELECT COUNT(*) FROM memberships WHERE city_id = $1) WHERE id = $1', [cityId]);
    }

    // 4. Update auth credentials to point to the new human
    // 5. Inscribe into house lineage
    const houseName = input.houseName?.trim() || input.dynastyName?.trim() || existingHouse?.house_name || 'Founding House';

    // Keep the active Family & House model updated so every new generation is visible in-game.
    let houseRow = (await tx.query<{ id: string }>('SELECT id FROM houses WHERE account_id = $1 OR email = $1 FOR UPDATE', [input.email])).rows[0];
    if (!houseRow) {
      const houseId = `HOUSE-${newHumanId.slice(2)}`;
      houseRow = (await tx.query<{ id: string }>('INSERT INTO houses (id,account_id,email,house_name,motto,founder_human_id,legacy_points,dynasty_legacy,generation,status,total_wealth_generated) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id', [houseId, input.email, input.email, houseName, 'From the Red Dust We Build Eternity', newHumanId, Math.floor(Number(prevHuman?.legacy ?? 0) * 0.25), Math.floor(Number(prevHuman?.legacy ?? 0) * 0.25), 1, 'ACTIVE', 0])).rows[0];
    }
    const nextGeneration = (await tx.query<{ generation: number }>('SELECT COALESCE(MAX(generation), 0) + 1 AS generation FROM house_lineage_records WHERE house_id = $1', [houseRow.id])).rows[0]?.generation ?? 1;
    await tx.query('UPDATE house_lineage_records SET is_incumbent = false WHERE house_id = $1', [houseRow.id]);
    await tx.query('INSERT INTO house_lineage_records (id,house_id,human_id,predecessor_human_id,generation,name,title,birth_game_day,is_incumbent,legacy_score) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9) ON CONFLICT (id) DO NOTHING', [crypto.randomUUID(), houseRow.id, newHumanId, prevHuman?.id ?? null, nextGeneration, input.displayName, 'House Successor', worldDay, Math.floor(Number(prevHuman?.legacy ?? 0) * 0.25)]);
    await tx.query('UPDATE houses SET legacy_points = legacy_points + $1 WHERE id = $2', [Math.floor(Number(prevHuman?.legacy ?? 0) * 0.25), houseRow.id]);
    await tx.query('UPDATE houses SET current_human_id = $1, generation = $2 WHERE id = $3', [newHumanId, nextGeneration, houseRow.id]);
    // A new adult starts with a fresh estate, but still carries the family's
    // equipped heirlooms and their active house benefits.
    await tx.query('UPDATE house_heirlooms SET equipped_by_human_id = $1 WHERE equipped_by_human_id = $2', [newHumanId, prevHuman?.id ?? '']);

    const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
    const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
    await tx.query('UPDATE houses SET current_human_id = $1, generation = $2 WHERE id = $3', [newHumanId, nextGeneration, houseRow.id]);
    await tx.query('INSERT INTO auth_sessions (id,account_id,human_id,token_hash,expires_at) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), cred.account_id, newHumanId, await digest(token), expires]);

    return {
      ok: true,
      reborn: true,
      human: { id: newHumanId, displayName: input.displayName, email: input.email, life_status: 'active' },
      token,
      expiresAt: expires,
      maxAge: SESSION_DAYS * 86400,
    };
  });
}

export async function claimHeirIdentity(repository: PostgresRepository, input: { email: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const cred = (await tx.query<{ account_id: string; house_id: string; human_id: string; email: string }>(`SELECT a.id AS account_id, a.house_id, a.email,
      COALESCE(h.current_human_id, (SELECT l.human_id FROM house_lineage_records l WHERE l.house_id = a.house_id ORDER BY l.generation DESC, l.created_at DESC LIMIT 1)) AS human_id
      FROM auth_accounts a JOIN houses h ON h.id = a.house_id WHERE a.email = $1`, [input.email])).rows[0];
    if (!cred) throw new Error('Account not found');
    const predecessor = (await tx.query<{ id: string; display_name: string; life_status: string }>('SELECT id, display_name, life_status FROM humans WHERE id = $1', [cred.human_id])).rows[0];
    if (!predecessor || !['deceased', 'estate'].includes(predecessor.life_status)) {
      throw new Error('An heir can be claimed only after mortality or during an estate period');
    }
    const plan = (await tx.query<{ successor_human_id: string; successor_name: string }>('SELECT successor_human_id, successor_name FROM succession_plans WHERE human_id = $1', [cred.human_id])).rows[0];
    if (!plan?.successor_human_id) throw new Error('No designated successor registered for this character');

    const successor = (await tx.query<{ id: string; display_name: string; life_status: string }>('SELECT id, display_name, life_status FROM humans WHERE id = $1', [plan.successor_human_id])).rows[0];
    if (!successor || successor.life_status !== 'active') throw new Error('Designated successor is not currently active');

    const world = await tx.query<{ game_day: number }>("SELECT game_day FROM world_state WHERE id = 'WORLD'");
    const gameDay = Number(world.rows[0]?.game_day ?? 1);
    const house = (await tx.query<{ id: string; house_name: string }>('SELECT id, house_name FROM houses WHERE email = $1 FOR UPDATE', [input.email])).rows[0];
    if (house) {
      await tx.query('UPDATE house_lineage_records SET is_incumbent = false WHERE house_id = $1', [house.id]);
      const nextGeneration = (await tx.query<{ generation: number }>('SELECT COALESCE(MAX(generation), 0) + 1 AS generation FROM house_lineage_records WHERE house_id = $1', [house.id])).rows[0]?.generation ?? 1;
      await tx.query('INSERT INTO house_lineage_records (id,house_id,human_id,predecessor_human_id,generation,name,title,birth_game_day,is_incumbent,legacy_score) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9) ON CONFLICT (id) DO UPDATE SET is_incumbent = true', [crypto.randomUUID(), house.id, successor.id, cred.human_id, nextGeneration, successor.display_name, 'Designated Heir', gameDay, 0]);
    }

    // Equipped heirlooms are family assets: the designated successor carries
    // them into the next generation instead of leaving their active benefits
    // attached to the deceased identity.
    await tx.query('UPDATE house_heirlooms SET equipped_by_human_id = $1 WHERE equipped_by_human_id = $2', [successor.id, cred.human_id]);

    // Make succession visible in the same world timeline as mortality and
    // rebirth. This is the player-facing confirmation that the next
    // generation is now the active character, even when estate settlement
    // happened automatically at the moment of death.
    await tx.query("INSERT INTO world_events (id,game_day,event_type,title,details) VALUES ($1,$2,'human.succession_claimed',$3,$4) ON CONFLICT DO NOTHING", [`SUCCESSION-CLAIM-${cred.human_id}-${successor.id}`, gameDay, `${successor.display_name} continued the house`, JSON.stringify({ predecessorId: cred.human_id, successorId: successor.id, houseName: house?.house_name ?? null })]);
    await tx.query("INSERT INTO notifications (id,human_id,notification_type,title,body,entity_id) VALUES ($1,$2,'life','House succession confirmed',$3,$4) ON CONFLICT DO NOTHING", [`SUCCESSION-NOTICE-${cred.human_id}-${successor.id}`, successor.id, `You now continue ${predecessor.display_name}'s house as the designated heir.`, predecessor.id]);

    const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
    const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
    await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [successor.id, house.id]);
    await tx.query('INSERT INTO auth_sessions (id,account_id,human_id,token_hash,expires_at) VALUES ($1,$2,$3,$4,$5)', [crypto.randomUUID(), cred.account_id, successor.id, await digest(token), expires]);

    return {
      ok: true,
      claimed: true,
      human: successor,
      token,
      expiresAt: expires,
      maxAge: SESSION_DAYS * 86400,
    };
  });
}

export async function deleteAccount(
  repository: PostgresRepository,
  input: { humanId: string; email: string },
): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    // 1. Mark human as deceased
    await tx.query("UPDATE humans SET life_status = 'deceased' WHERE id = $1", [input.humanId]);
    // 2. Delete credentials
    const account = (await tx.query<{ id: string; house_id: string }>('SELECT id, house_id FROM auth_accounts WHERE email = $1', [input.email])).rows[0];
    await tx.query('DELETE FROM auth_credentials WHERE human_id = $1', [input.humanId]);
    // 3. Delete action tokens
    await tx.query('DELETE FROM auth_action_tokens WHERE account_id = $1', [account?.id]);
    // 4. Delete active sessions
    await tx.query('DELETE FROM auth_sessions WHERE account_id = $1', [account?.id]);
    // 5. Clear login attempts
    await tx.query('DELETE FROM auth_login_attempts WHERE email = $1', [input.email]);
    // 6. Release house email so the email can be re-registered
    await tx.query("UPDATE houses SET email = 'deleted-' || id || '-' || email, account_id = 'deleted-' || id || '-' || account_id, status = 'CLOSED' WHERE email = $1", [input.email]);
    // 7. Enqueue outbox notification
    await enqueueOutbox(tx, {
      eventKey: `account-deleted:${input.humanId}`,
      topic: 'world_activity',
      aggregateType: 'human',
      aggregateId: input.humanId,
      payload: { type: 'world_activity', category: 'identity', action: 'account_deleted', humanId: input.humanId },
    });
    return { ok: true, message: 'Account deleted successfully' };
  });
}
