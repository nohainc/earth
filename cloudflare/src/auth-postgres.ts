import type { PostgresRepository } from './repository';
import { calculateStarterPackage } from './starter-package.ts';
import { base64ToBytes, bytesToBase64, derivePassword, digest, SESSION_DAYS } from './auth-crypto.ts';
import { enqueueOutbox } from './outbox-postgres.ts';
import { refreshV5SettlementProfilesForHouse } from './v5-settlement-profiles-postgres.ts';
import { readAuthoritativeGameTime } from './world-clock-postgres.ts';

export async function registerIdentity(repository: PostgresRepository, input: { email: string; personName: string; houseSurname: string; password: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    if ((await tx.query('SELECT 1 FROM auth_accounts WHERE email = $1', [input.email])).rows[0]) throw new Error('Email is already registered');
    const worldDay = (await readAuthoritativeGameTime(tx)).gameDay;
    const starter = calculateStarterPackage();
    const humanId = `H-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const accountId = `account-${humanId.toLowerCase()}`;
    const houseId = `HOUSE-${humanId.slice(2)}`;
    const economicId = `ECON-${houseId}`;
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const passwordHash = await derivePassword(input.password, salt, 100000);
    await tx.query('INSERT INTO auth_accounts (id,email,password_hash,password_salt,password_iterations) VALUES ($1,$2,$3,$4,100000)', [accountId, input.email, passwordHash, bytesToBase64(salt)]);
    await tx.query('INSERT INTO houses (id,account_id,house_name,motto,created_game_day) VALUES ($1,$2,$3,$4,$5)', [houseId, accountId, `House ${input.houseSurname}`, 'From the Red Dust We Build Eternity', worldDay]);
    await tx.query('UPDATE auth_accounts SET house_id = $1 WHERE id = $2', [houseId, accountId]);
    await tx.query('INSERT INTO humans (id,account_id,house_id,display_name,birth_game_day,age_years) VALUES ($1,$2,$3,$4,$5,31)', [humanId, accountId, houseId, `${input.personName} ${input.houseSurname}`, worldDay - 31 * 365]);
    await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
    await tx.query("INSERT INTO owner_registry (id,owner_type,economic_id) VALUES ($1,'HOUSE',$2)", [houseId, economicId]);
    await refreshV5SettlementProfilesForHouse(tx, houseId, worldDay);
    await tx.query('INSERT INTO house_onboarding_progress (house_id) VALUES ($1) ON CONFLICT (house_id) DO NOTHING', [houseId]);
    await tx.query('INSERT INTO house_entry_support (house_id, entry_game_day, eligible_until_game_day) VALUES ($1, $2, $3) ON CONFLICT (house_id) DO NOTHING', [houseId, worldDay, worldDay + 30]);
    await tx.query('SELECT earth_provision_house_economy($1)', [economicId]);
    const assets = await tx.query<{ id: number; code: string; unit_scale: string }>('SELECT id, code, unit_scale::TEXT FROM economic_assets WHERE id BETWEEN 1 AND 6');
    const displayAmounts: Record<string, number> = {
      CREDIT: starter.credits,
      MATERIAL: starter.resources.material,
      COMPONENTS: starter.resources.components,
      ENERGY: starter.resources.energy,
      COMPUTE: starter.resources.compute,
      FOOD: starter.resources.food,
    };
    const starterAssets = assets.rows
      .map((asset) => [asset.id, BigInt(displayAmounts[asset.code] ?? 0) * BigInt(asset.unit_scale)] as const)
      .filter(([, amount]) => amount > 0n);
    for (const [assetId, amount] of starterAssets) {
      await tx.query('SELECT earth_issue_starter_package($1,$2,$3,$4,$5)', [`starter:${houseId}:${assetId}`, worldDay, economicId, assetId, amount]);
    }
    await enqueueOutbox(tx, { eventKey: `starter-package:${humanId}`, topic: 'world_activity', aggregateType: 'human', aggregateId: humanId, payload: { type: 'world_activity', category: 'identity', action: 'starter_package_created', humanId, gameDay: worldDay } });
    return { ok: true, human: { id: humanId, email: input.email, displayName: `${input.personName} ${input.houseSurname}` }, starterPackage: starter };
  });
}

export async function updateDisplayName(repository: PostgresRepository, input: { humanId: string; displayName?: string; epitaph?: string }): Promise<Record<string, unknown>> {
  if (input.displayName) await repository.query('UPDATE humans SET display_name = $1 WHERE id = $2', [input.displayName, input.humanId]);
  const human = (await repository.query('SELECT id, display_name, epitaph FROM humans WHERE id = $1 AND status = \'ACTIVE\'', [input.humanId])).rows[0];
  if (!human) throw new Error('Human not found');
  return { ok: true, human };
}

export async function updateHumanTestament(repository: PostgresRepository, input: { humanId: string; testament: string }): Promise<Record<string, unknown>> {
  const result = await repository.query<{ id: string; epitaph: string | null }>(
    `UPDATE humans
        SET epitaph = NULLIF($1, '')
      WHERE id = $2 AND status = 'ACTIVE'
      RETURNING id, epitaph`,
    [input.testament, input.humanId],
  );
  if (!result.rows[0]) throw new Error('Only the active Human may edit a testament');
  return { ok: true, humanId: result.rows[0].id, testament: result.rows[0].epitaph };
}

export async function loginIdentity(repository: PostgresRepository, input: { email: string; password: string; otp: string; validTotp: (secret: string, code: string) => Promise<boolean> }): Promise<Record<string, unknown>> {
  const credential = (await repository.query('SELECT a.id AS account_id, a.house_id, a.password_hash, a.password_salt, a.password_iterations, a.email_verified_at, a.mfa_enabled, a.mfa_secret, h.status AS house_status, human.status AS human_status FROM auth_accounts a JOIN houses h ON h.id = a.house_id JOIN humans human ON human.id = h.current_human_id WHERE a.email = $1', [input.email])).rows[0];
  if (!credential || credential.house_status !== 'ACTIVE' || credential.human_status !== 'ACTIVE') throw new Error('Invalid email or password');
  if (!credential.email_verified_at) throw new Error('Verify your email before signing in');
  if (await derivePassword(input.password, base64ToBytes(credential.password_salt), Number(credential.password_iterations)) !== credential.password_hash) throw new Error('Invalid email or password');
  if (credential.mfa_enabled && (!credential.mfa_secret || !(await input.validTotp(credential.mfa_secret, input.otp)))) throw new Error('Authenticator code required');
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
  await repository.query('INSERT INTO auth_sessions (id,account_id,human_id,token_hash,expires_at) SELECT $1,$2,h.current_human_id,$3,$4 FROM houses h WHERE h.id = $5', [crypto.randomUUID(), credential.account_id, await digest(token), expires, credential.house_id]);
  const human = (await repository.query('SELECT id, house_id, display_name, status FROM humans WHERE id = (SELECT current_human_id FROM houses WHERE id = $1)', [credential.house_id])).rows[0];
  return { ok: true, human, token, expiresAt: expires, maxAge: SESSION_DAYS * 86400 };
}

export async function rebornIdentity(): Promise<Record<string, unknown>> { throw new Error('House succession is handled by the lifecycle service'); }
export async function claimHeirIdentity(): Promise<Record<string, unknown>> { throw new Error('House succession is handled by the lifecycle service'); }

export async function deleteAccount(repository: PostgresRepository, input: { humanId: string; email: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const account = (await tx.query('SELECT id, house_id FROM auth_accounts WHERE email = $1', [input.email])).rows[0];
    if (!account) throw new Error('Account not found');
    const day = (await readAuthoritativeGameTime(tx)).gameDay;
    await tx.query("UPDATE humans SET status = 'DECEASED', death_game_day = $1 WHERE id = $2", [day, input.humanId]);
    await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE account_id = $1', [account.id]);
    await tx.query('DELETE FROM auth_action_tokens WHERE account_id = $1', [account.id]);
    return { ok: true, message: 'Account deactivated successfully' };
  });
}
