import { withRepository } from './repository.ts';
import {
  bytesToBase64,
  digest,
  SESSION_DAYS,
  validTotp,
} from './auth-crypto.ts';

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

export function extractToken(request: Request): string | null {
  const cookieTok = cookieValue(request, 'earth_session');
  if (cookieTok) return cookieTok;
  const authHeader = request.headers.get('Authorization') ?? request.headers.get('authorization');
  if (authHeader && /^Bearer\s+/i.test(authHeader)) {
    return authHeader.replace(/^Bearer\s+/i, '').trim();
  }
  return null;
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
  const token = extractToken(request);
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
         AND (humans.life_status = 'active' OR ($2 = 1 AND humans.life_status IN ('estate', 'deceased')) )`,
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

export function maskEmail(email: string): string {
  const parts = email.split('@');
  if (parts.length !== 2) return '***@***';
  const name = parts[0];
  const domain = parts[1];
  const maskedName =
    name.length <= 2
      ? `${name[0]}*`
      : `${name[0]}${'*'.repeat(Math.max(1, name.length - 2))}${name[name.length - 1]}`;
  return `${maskedName}@${domain}`;
}

export async function issueActionToken(
  env: Env,
  humanId: string,
  action: 'verify_email' | 'reset_password',
  email: string,
  correlationId?: string,
): Promise<{ correlationId: string; accepted: boolean; messageId?: string | null }> {
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await digest(token);
  const id = crypto.randomUUID();
  const corrId = correlationId || crypto.randomUUID();
  const masked = maskEmail(email);
  const expires = new Date(
    Date.now() + (action === 'verify_email' ? 24 : 1) * 3600000,
  ).toISOString();
  const result = await withRepository(env, (repository) =>
    repository.query(
      'INSERT INTO auth_action_tokens (id, human_id, token_hash, action, expires_at) VALUES ($1,$2,$3,$4,$5)',
      [id, humanId, tokenHash, action, expires],
    ),
  );
  const path =
    action === 'verify_email'
      ? `/app?verify_token=${encodeURIComponent(token)}`
      : `/app?reset_token=${encodeURIComponent(token)}`;
  if (!env.EMAIL || !env.EMAIL_FROM) {
    await withRepository(env, (repository) =>
      repository.query(
        'INSERT INTO auth_email_deliveries (id, correlation_id, human_id, recipient_masked, action, status, error_code, error_message) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
        [crypto.randomUUID(), corrId, humanId, masked, action, 'failed', 'UNCONFIGURED', 'Transactional email is not configured'],
      ),
    ).catch(() => {});
    console.error(
      JSON.stringify({
        event: 'transactional_email_failed',
        correlationId: corrId,
        humanId,
        recipientMasked: masked,
        action,
        code: 'UNCONFIGURED',
        message: 'Transactional email is not configured',
      }),
    );
    throw new Error('Transactional email is not configured');
  }
  const subject =
    action === 'verify_email'
      ? 'Verify your EARTH identity'
      : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}\n\nThis link expires soon and can only be used once.`;
  try {
    const delivery = await env.EMAIL.send({
      to: email,
      from: { email: env.EMAIL_FROM, name: 'EARTH Identity' },
      subject,
      text,
      html: `<p>${subject}</p><p><a href="https://earthuc.com${path}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>`,
    });
    await withRepository(env, (repository) =>
      repository.query(
        'INSERT INTO auth_email_deliveries (id, correlation_id, human_id, recipient_masked, action, status, provider_message_id) VALUES ($1,$2,$3,$4,$5,$6,$7)',
        [crypto.randomUUID(), corrId, humanId, masked, action, 'accepted', delivery?.messageId ?? null],
      ),
    ).catch(() => {});
    console.info(
      JSON.stringify({
        event: 'transactional_email_accepted',
        correlationId: corrId,
        humanId,
        recipientMasked: masked,
        action,
        messageId: delivery?.messageId ?? null,
      }),
    );
    return { correlationId: corrId, accepted: true, messageId: delivery?.messageId ?? null };
  } catch (error) {
    const details =
      error && typeof error === 'object'
        ? (error as { code?: unknown; message?: unknown })
        : {};
    const errorCode = String(details.code ?? 'unknown');
    const errorMessage = String(details.message ?? 'unknown');
    await withRepository(env, (repository) =>
      repository.query(
        'INSERT INTO auth_email_deliveries (id, correlation_id, human_id, recipient_masked, action, status, error_code, error_message) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
        [crypto.randomUUID(), corrId, humanId, masked, action, 'failed', errorCode, errorMessage],
      ),
    ).catch(() => {});
    console.error(
      JSON.stringify({
        event: 'transactional_email_failed',
        correlationId: corrId,
        humanId,
        recipientMasked: masked,
        action,
        code: errorCode,
        message: errorMessage,
      }),
    );
    // Do not let a failed delivery consume the resend throttle window.
    await withRepository(env, (repository) =>
      repository.query('DELETE FROM auth_action_tokens WHERE id = $1', [id]),
    );
    throw error;
  }
}
