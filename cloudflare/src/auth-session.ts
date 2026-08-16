import { withRepository } from './repository';
import {
  bytesToBase64,
  digest,
  SESSION_DAYS,
  validTotp,
} from './auth-crypto';

export interface AuthenticatedHuman {
  id: string;
  display_name: string;
  email: string;
  life_status: string;
}

export function cookieValue(request: Request, name: string): string | null {
  const cookies =
    request.headers
      .get('Cookie')
      ?.split(';')
      .map((part) => part.trim()) ?? [];
  const value = cookies.find((part) => part.startsWith(`${name}=`));
  return value ? decodeURIComponent(value.slice(name.length + 1)) : null;
}

export function sessionCookie(token: string, maxAge: number): string {
  return `earth_session=${encodeURIComponent(
    token,
  )}; Max-Age=${maxAge}; Path=/; HttpOnly; Secure; SameSite=Lax`;
}

export async function currentHuman(
  request: Request,
  env: Env,
  allowEstate = false,
): Promise<AuthenticatedHuman | null> {
  const token = cookieValue(request, 'earth_session');
  if (!token) return null;
  const tokenHash = await digest(token);
  const result = await withRepository(env, (repository) =>
    repository.query<AuthenticatedHuman>(
      `SELECT humans.id, humans.display_name, humans.life_status, auth_credentials.email
       FROM auth_sessions
       JOIN humans ON humans.id = auth_sessions.human_id
       JOIN auth_credentials ON auth_credentials.human_id = humans.id
       WHERE auth_sessions.token_hash = $1
         AND auth_sessions.revoked_at IS NULL
         AND auth_sessions.expires_at > CURRENT_TIMESTAMP
         AND (humans.life_status = 'active' OR ($2 = 1 AND humans.life_status = 'estate'))`,
      [tokenHash, allowEstate ? 1 : 0],
    ),
  );
  return result?.rows[0] ?? null;
}

export async function sensitiveActionAllowed(
  env: Env,
  humanId: string,
  otp?: string,
): Promise<boolean> {
  const result = await withRepository(env, (repository) =>
    repository.query<{ mfa_enabled: boolean; mfa_secret: string | null }>(
      'SELECT mfa_enabled, mfa_secret FROM auth_credentials WHERE human_id = $1',
      [humanId],
    ),
  );
  const credential = result?.rows[0];
  return (
    !credential?.mfa_enabled ||
    Boolean(credential.mfa_secret && (await validTotp(credential.mfa_secret, otp ?? '')))
  );
}

export async function issueActionToken(
  env: Env,
  humanId: string,
  action: 'verify_email' | 'reset_password',
  email: string,
): Promise<void> {
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await digest(token);
  const id = crypto.randomUUID();
  const expires = new Date(
    Date.now() + (action === 'verify_email' ? 24 : 1) * 3600000,
  ).toISOString();
  const result = await withRepository(env, (repository) =>
    repository.query(
      'INSERT INTO auth_action_tokens (id, human_id, token_hash, action, expires_at) VALUES ($1,$2,$3,$4,$5)',
      [id, humanId, tokenHash, action, expires],
    ),
  );
  if (!result) throw new Error('PostgreSQL authentication repository is unavailable');
  if (!env.EMAIL || !env.EMAIL_FROM) {
    throw new Error('Transactional email is not configured');
  }
  const path =
    action === 'verify_email'
      ? `/app?verify_token=${encodeURIComponent(token)}`
      : `/app?reset_token=${encodeURIComponent(token)}`;
  const subject =
    action === 'verify_email'
      ? 'Verify your EARTH identity'
      : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}\n\nThis link expires soon and can only be used once.`;
  try {
    const delivery = await env.EMAIL.send({
      to: email,
      from: { email: env.EMAIL_FROM, name: 'EARTH Identity' },
      replyTo: env.EMAIL_REPLY_TO,
      subject,
      text,
      html: `<p>${subject}</p><p><a href="https://earthuc.com${path}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>`,
    });
    console.info(
      JSON.stringify({
        event: 'transactional_email_accepted',
        action,
        messageId: delivery?.messageId ?? null,
      }),
    );
  } catch (error) {
    const details =
      error && typeof error === 'object'
        ? (error as { code?: unknown; message?: unknown })
        : {};
    console.error(
      JSON.stringify({
        event: 'transactional_email_failed',
        action,
        code: String(details.code ?? 'unknown'),
        message: String(details.message ?? 'unknown'),
      }),
    );
    // Do not let a failed delivery consume the resend throttle window.
    await withRepository(env, (repository) =>
      repository.query('DELETE FROM auth_action_tokens WHERE id = $1', [id]),
    );
    throw error;
  }
}
