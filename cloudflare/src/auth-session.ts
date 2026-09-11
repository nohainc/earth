import { withRepository } from './repository.ts';
import {
  bytesToBase64,
  digest,
  SESSION_DAYS,
  validTotp,
} from './auth-crypto.ts';
export { cookieValue, extractToken } from './auth-token.ts';
import { extractTokens } from './auth-token.ts';
export interface AuthenticatedHuman {
  id: string;
  house_id: string;
  account_id: string;
  display_name: string;
  email: string;
  life_status: string;
}

export interface AuthenticatedHouse {
  id: string;
  account_id: string;
  current_human_id: string;
  house_name: string;
  economic_id: string;
}

/** Resolve the persistent player principal from the session, independent of its current Human. */
export async function currentHouse(request: Request, env: Env): Promise<AuthenticatedHouse | null> {
  for (const token of extractTokens(request)) {
    const tokenHash = await digest(token);
    const result = await withRepository(env, (repository) => repository.query<AuthenticatedHouse>(
      `SELECT h.id, a.id AS account_id, h.current_human_id, h.house_name,
              owner.economic_id::TEXT AS economic_id
         FROM auth_sessions s
         JOIN auth_accounts a ON a.id = s.account_id
         JOIN houses h ON h.id = a.house_id
         JOIN owner_registry owner ON owner.id = h.id AND owner.owner_type = 'house'
        WHERE s.token_hash = $1
          AND s.revoked_at IS NULL
          AND s.expires_at > CURRENT_TIMESTAMP
          AND h.status = 'ACTIVE'
          AND h.current_human_id IS NOT NULL
          AND owner.status = 'active'`,
      [tokenHash],
    ));
    if (result?.rows[0]) return result.rows[0];
  }
  return null;
}

/** Resolve the House economic owner for value-bearing operations. */
export async function houseEconomicOwner(request: Request, env: Env): Promise<AuthenticatedHouse | null> {
  return currentHouse(request, env);
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
  for (const token of extractTokens(request)) {
    const tokenHash = await digest(token);
    const result = await withRepository(env, (repository) =>
      repository.query<AuthenticatedHuman>(
        `SELECT humans.id, humans.house_id, auth_sessions.account_id,
                humans.display_name, humans.life_status, auth_accounts.email
         FROM auth_sessions
         JOIN auth_accounts ON auth_accounts.id = auth_sessions.account_id
         JOIN houses ON houses.id = auth_accounts.house_id
         JOIN humans ON humans.id = houses.current_human_id
         WHERE auth_sessions.token_hash = $1
           AND auth_sessions.revoked_at IS NULL
           AND auth_sessions.expires_at > CURRENT_TIMESTAMP
           AND houses.status = 'ACTIVE'
           AND humans.account_status = 'active'
           AND (humans.life_status = 'active' OR ($2 = 1 AND humans.life_status IN ('estate', 'deceased')) )`,
        [tokenHash, allowEstate ? 1 : 0],
      ),
    );
    if (result?.rows[0]) return result.rows[0];
  }
  return null;
}

export async function sensitiveActionAllowed(
  env: Env,
  humanId: string,
  otp?: string,
): Promise<boolean> {
  const result = await withRepository(env, (repository) =>
    repository.query<{ mfa_enabled: boolean; mfa_secret: string | null }>(
      'SELECT a.mfa_enabled, a.mfa_secret FROM auth_accounts a JOIN houses h ON h.id = a.house_id WHERE h.current_human_id = $1',
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

import { sendSmtpEmail } from './email-smtp.ts';

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
      `INSERT INTO auth_action_tokens (id, account_id, human_id, token_hash, action, expires_at)
       SELECT $1, a.id, $2, $3, $4, $5
       FROM auth_accounts a JOIN humans h ON h.house_id = a.house_id
       WHERE h.id = $2`,
      [id, humanId, tokenHash, action, expires],
    ),
  );
  const path =
    action === 'verify_email'
      ? `/app?verify_token=${encodeURIComponent(token)}`
      : `/app?reset_token=${encodeURIComponent(token)}`;
  const subject =
    action === 'verify_email'
      ? 'Verify your EARTH identity'
      : 'Reset your EARTH password';
  const text = `${subject}\n\nOpen this link to continue: https://earthuc.com${path}\n\nThis link expires soon and can only be used once.`;
  const html = `<p>${subject}</p><p><a href="https://earthuc.com${path}">Continue securely</a></p><p>This link expires soon and can only be used once.</p>`;
  const smtpUser = (env as unknown as Record<string, string | undefined>).SMTP_USER || 'vitalii@nohainc.com';
  const gmailAppPassword = (env as unknown as Record<string, string | undefined>).GMAIL_APP_PASSWORD;
  const fromEmail = env.EMAIL_FROM || 'earth@nohainc.com';

  try {
    let deliveryMessageId: string | null = null;
    if (gmailAppPassword && smtpUser) {
      const delivery = await sendSmtpEmail({
        to: email,
        from: fromEmail,
        subject,
        text,
        html,
        smtpUser,
        gmailAppPassword,
      });
      deliveryMessageId = delivery.messageId;
    } else if (env.EMAIL) {
      const delivery = await env.EMAIL.send({
        to: email,
        from: { email: env.EMAIL_FROM, name: 'EARTH Identity' },
        subject,
        text,
        html,
      });
      deliveryMessageId = delivery?.messageId ?? null;
    } else {
      throw new Error('Transactional email is not configured');
    }
    await withRepository(env, (repository) =>
      repository.query(
        'INSERT INTO auth_email_deliveries (id, correlation_id, human_id, recipient_masked, action, status, provider_message_id) VALUES ($1,$2,$3,$4,$5,$6,$7)',
        [crypto.randomUUID(), corrId, humanId, masked, action, 'accepted', deliveryMessageId],
      ),
    ).catch(() => {});
    console.info(
      JSON.stringify({
        event: 'transactional_email_accepted',
        correlationId: corrId,
        humanId,
        recipientMasked: masked,
        action,
        messageId: deliveryMessageId,
      }),
    );
    return { correlationId: corrId, accepted: true, messageId: deliveryMessageId };
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
