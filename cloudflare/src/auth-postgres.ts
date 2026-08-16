import type { PostgresRepository } from './repository';
import { calculateStarterPackage, economicStartIndex } from './starter-package';

const encoder = new TextEncoder();
const SESSION_DAYS = 7;

function bytesToBase64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

function base64ToBytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

async function derivePassword(password: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256);
  return bytesToBase64(new Uint8Array(bits));
}

async function digest(value: string): Promise<string> {
  return bytesToBase64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))));
}

export async function registerIdentity(repository: PostgresRepository, input: { email: string; displayName: string; password: string }): Promise<Record<string, unknown>> {
  return repository.transaction(async (tx) => {
    const existing = await tx.query('SELECT human_id FROM auth_credentials WHERE email = $1', [input.email]);
    if (existing.rows[0]) throw new Error('Email is already registered');
    const world = await tx.query<{ game_day: number; living_cost_index: string }>("SELECT game_day, living_cost_index FROM world_state WHERE id = 'WORLD'");
    const referencePrice = await tx.query<{ reference_price: string }>("SELECT COALESCE(AVG(price), 50) AS reference_price FROM market_prices WHERE product IN ('components', 'energy')");
    const worldDay = Number(world.rows[0]?.game_day ?? 184);
    const starter = calculateStarterPackage(world.rows[0]?.living_cost_index ?? 1, economicStartIndex(referencePrice.rows[0]?.reference_price ?? 50));
    const humanId = `H-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const accountId = `account-${humanId.toLowerCase()}`;
    const businessId = `B-${humanId.slice(2)}`;
    const technologyId = `TECH-${humanId.slice(2)}`;
    const machineId = `M-${humanId.slice(2)}-01`;
    const researchId = `R-${humanId.slice(2)}`;
    const assistantId = `AI-${humanId.slice(2)}-01`;
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const iterations = 100000;
    const passwordHash = await derivePassword(input.password, salt, iterations);
    await tx.query('INSERT INTO humans (id,account_id,display_name,age_years,standing,legacy,political_eligibility_game_day) VALUES ($1,$2,$3,31,0,0,$4)', [humanId, accountId, input.displayName, worldDay + 3]);
    await tx.query('INSERT INTO auth_credentials (human_id,email,password_hash,password_salt,password_iterations) VALUES ($1,$2,$3,$4,$5)', [humanId, input.email, passwordHash, bytesToBase64(salt), iterations]);
    await tx.query("INSERT INTO account_balances (account_id,owner_id,balance,currency) VALUES ($1,$2,$3,'CREDIT')", [accountId, humanId, starter.credits]);
    for (const [resource, amount] of Object.entries(starter.resources)) await tx.query('INSERT INTO resource_balances (owner_id,resource,amount) VALUES ($1,$2,$3)', [humanId, resource, amount]);
    await tx.query("INSERT INTO businesses (id,owner_id,name,policy,condition,sector) VALUES ($1,$2,$3,'reliability',100,'maintenance')", [businessId, humanId, `${input.displayName} Works`]);
    await tx.query('INSERT INTO business_financials (business_id,last_game_day) VALUES ($1,$2)', [businessId, worldDay]);
    await tx.query('INSERT INTO business_shares (business_id,holder_id,shares) VALUES ($1,$2,100)', [businessId, humanId]);
    await tx.query('INSERT INTO technologies (id,name,owner_id,progress) VALUES ($1,$2,$3,0)', [technologyId, `${input.displayName} Adaptive System`, humanId]);
    await tx.query("INSERT INTO machines (id,owner_id,name,machine_type,condition,utilization,maintenance_due,productive_capacity) VALUES ($1,$2,$3,'service-robot',100,25,0,1)", [machineId, humanId, `${input.displayName} Service Unit`]);
    await tx.query("INSERT INTO business_assets (business_id,machine_id,assigned_game_day,assigned_by) VALUES ($1,$2,$3,'starter-package')", [businessId, machineId, worldDay]);
    await tx.query("INSERT INTO research_projects (id,technology_id,owner_id,budget,progress,status,started_game_day) VALUES ($1,$2,$3,0,0,'active',$4)", [researchId, technologyId, humanId, worldDay]);
    await tx.query("INSERT INTO ai_assistants (id,owner_id,tier,policy,enabled) VALUES ($1,$2,'basic','recommend',true)", [assistantId, humanId]);
    await tx.query("INSERT INTO ownership_events (id,asset_type,asset_id,from_owner_id,to_owner_id,quantity,reason_type,reason_id,game_day) VALUES ($1,'BUSINESS',$2,NULL,$3,1,'starter_package',$3,$4),($5,'BUSINESS_SHARES',$2,NULL,$3,100,'starter_package',$3,$4),($6,'MACHINE',$7,NULL,$3,1,'starter_package',$3,$4)", [crypto.randomUUID(), businessId, humanId, worldDay, crypto.randomUUID(), crypto.randomUUID(), machineId]);
    return { ok: true, human: { id: humanId, displayName: input.displayName, email: input.email }, starterPackage: starter };
  });
}

export async function loginIdentity(repository: PostgresRepository, input: { email: string; password: string; otp: string; validTotp: (secret: string, code: string) => Promise<boolean> }): Promise<Record<string, unknown>> {
  const attempt = (await repository.query<{ window_started_at: string; attempt_count: number; blocked_until: string | null }>('SELECT window_started_at, attempt_count, blocked_until FROM auth_login_attempts WHERE email = $1', [input.email])).rows[0];
  if (attempt?.blocked_until && new Date(attempt.blocked_until).getTime() > Date.now()) throw new Error('Too many login attempts. Try again later.');
  const credential = (await repository.query<{ human_id: string; password_hash: string; password_salt: string; password_iterations: number; email_verified_at: string | null; mfa_enabled: boolean; mfa_secret: string | null; life_status: string }>("SELECT auth_credentials.*, humans.life_status FROM auth_credentials JOIN humans ON humans.id = auth_credentials.human_id WHERE auth_credentials.email = $1", [input.email])).rows[0];
  if (credential?.life_status !== 'active') throw new Error('This Human is not currently active');
  if (!credential.email_verified_at) throw new Error('Verify your email before signing in');
  const matches = Boolean(input.password.length && await derivePassword(input.password, base64ToBytes(credential.password_salt), Number(credential.password_iterations)) === credential.password_hash);
  if (!matches) {
    const withinWindow = Boolean(attempt && Date.now() - new Date(attempt.window_started_at).getTime() < 15 * 60 * 1000);
    const count = withinWindow ? Number(attempt?.attempt_count ?? 0) + 1 : 1;
    const blockedUntil = count >= 5 ? new Date(Date.now() + 15 * 60 * 1000).toISOString() : null;
    await repository.query('INSERT INTO auth_login_attempts (email,window_started_at,attempt_count,blocked_until) VALUES ($1,CURRENT_TIMESTAMP,$2,$3) ON CONFLICT(email) DO UPDATE SET window_started_at = CASE WHEN $4 THEN auth_login_attempts.window_started_at ELSE CURRENT_TIMESTAMP END, attempt_count = $2, blocked_until = $3', [input.email, count, blockedUntil, withinWindow]);
    throw new Error('Invalid email or password');
  }
  if (credential.mfa_enabled && (!credential.mfa_secret || !(await input.validTotp(credential.mfa_secret, input.otp)))) throw new Error('Authenticator code required');
  await repository.query('DELETE FROM auth_login_attempts WHERE email = $1', [input.email]);
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const expires = new Date(Date.now() + SESSION_DAYS * 86400000).toISOString();
  await repository.query('INSERT INTO auth_sessions (id,human_id,token_hash,expires_at) VALUES ($1,$2,$3,$4)', [crypto.randomUUID(), credential.human_id, await digest(token), expires]);
  const human = (await repository.query('SELECT id, display_name FROM humans WHERE id = $1', [credential.human_id])).rows[0];
  return { ok: true, human, expiresAt: expires, token, maxAge: SESSION_DAYS * 86400 };
}
