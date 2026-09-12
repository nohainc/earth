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

export type ViewerContext = {
  accountId: string;
  houseId: string;
  currentHumanId: string;
};

export async function currentViewer(request: Request, env: Env): Promise<ViewerContext | null> {
  const human = await currentHuman(request, env);
  return human ? { accountId: human.account_id, houseId: human.house_id, currentHumanId: human.id } : null;
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
): Promise<{ correlationId: string; accepted: boolean; messageId?: string | null; auditPersisted?: boolean }> {
  const token = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await digest(token);
  const id = crypto.randomUUID();
  const corrId = correlationId || crypto.randomUUID();
  const masked = maskEmail(email);
  const previous = (await withRepository(env, (repository) => repository.query<{ status: string; provider_message_id: string | null }>(
    'SELECT status, provider_message_id FROM auth_email_deliveries WHERE correlation_id = $1',
    [corrId],
  )))?.rows[0];
  if (previous?.status === 'accepted') {
    return { correlationId: corrId, accepted: true, messageId: previous.provider_message_id, auditPersisted: true };
  }
  const expires = new Date(
    Date.now() + (action === 'verify_email' ? 24 : 1) * 3600000,
  ).toISOString();
  let accountId: string | null = null;
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
    const result = await withRepository(env, (repository) =>
      repository.query<{ account_id: string }>(
        `INSERT INTO auth_action_tokens (id, account_id, human_id, token_hash, action, expires_at)
         SELECT $1, a.id, $2, $3, $4, $5
         FROM auth_accounts a JOIN humans h ON h.house_id = a.house_id
         WHERE h.id = $2
         RETURNING account_id`,
         [id, humanId, tokenHash, action, expires],
      ),
    );
    if (!result?.rows[0]?.account_id) throw new Error('Authentication storage is unavailable');
    accountId = result.rows[0].account_id;
    let deliveryMessageId: string | null = null;
    let provider = 'unknown';
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
      provider = 'smtp';
    } else if (env.EMAIL) {
      const delivery = await env.EMAIL.send({
        to: email,
        from: { email: env.EMAIL_FROM, name: 'EARTH Identity' },
        subject,
        text,
        html,
      });
      deliveryMessageId = delivery?.messageId ?? null;
      provider = 'cloudflare_email';
    } else {
      throw new Error('Transactional email is not configured');
    }
    let auditPersisted = true;
    try {
      const audit = await withRepository(env, (repository) => repository.query(
        `INSERT INTO auth_email_deliveries
          (id, correlation_id, account_id, human_id, recipient_masked, action, provider, status, provider_message_id, accepted_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,CURRENT_TIMESTAMP)
         ON CONFLICT (correlation_id) DO UPDATE SET
           account_id = EXCLUDED.account_id,
           human_id = EXCLUDED.human_id,
           recipient_masked = EXCLUDED.recipient_masked,
           action = EXCLUDED.action,
           provider = EXCLUDED.provider,
           status = 'accepted',
           provider_message_id = EXCLUDED.provider_message_id,
           error_code = NULL,
           error_message = NULL,
           accepted_at = CURRENT_TIMESTAMP,
           failed_at = NULL,
           updated_at = CURRENT_TIMESTAMP
         RETURNING id`,
        [crypto.randomUUID(), corrId, accountId, humanId, masked, action, provider, 'accepted', deliveryMessageId],
      ));
      auditPersisted = Boolean(audit?.rows[0]);
    } catch (auditError) {
      auditPersisted = false;
      console.error(JSON.stringify({ event: 'transactional_email_audit_persistence_failed', correlationId: corrId, humanId, recipientMasked: masked, action, error: auditError instanceof Error ? auditError.message : String(auditError) }));
    }
    console.info(
      JSON.stringify({
        event: 'transactional_email_accepted',
        correlationId: corrId,
        humanId,
        recipientMasked: masked,
        action,
        messageId: deliveryMessageId,
        auditPersisted,
      }),
    );
    return { correlationId: corrId, accepted: true, messageId: deliveryMessageId, auditPersisted };
  } catch (error) {
    const details =
      error && typeof error === 'object'
        ? (error as { code?: unknown; message?: unknown })
        : {};
    const errorCode = String(details.code ?? 'unknown');
    const errorMessage = String(details.message ?? 'unknown');
    try {
      await withRepository(env, (repository) => repository.query(
        `INSERT INTO auth_email_deliveries
          (id, correlation_id, account_id, human_id, recipient_masked, action, provider, status, error_code, error_message, failed_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,CURRENT_TIMESTAMP)
         ON CONFLICT (correlation_id) DO UPDATE SET
           account_id = EXCLUDED.account_id,
           human_id = EXCLUDED.human_id,
           recipient_masked = EXCLUDED.recipient_masked,
           action = EXCLUDED.action,
           provider = EXCLUDED.provider,
           status = 'failed',
           provider_message_id = NULL,
           error_code = EXCLUDED.error_code,
           error_message = EXCLUDED.error_message,
           accepted_at = NULL,
           failed_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP`,
        [crypto.randomUUID(), corrId, accountId, humanId, masked, action, 'unavailable', 'failed', errorCode, errorMessage],
      ));
    } catch (auditError) {
      console.error(JSON.stringify({ event: 'transactional_email_audit_persistence_failed', correlationId: corrId, humanId, recipientMasked: masked, action, error: auditError instanceof Error ? auditError.message : String(auditError) }));
    }
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
    try {
      await withRepository(env, (repository) => repository.query('DELETE FROM auth_action_tokens WHERE id = $1', [id]));
    } catch (cleanupError) {
      console.error(JSON.stringify({ event: 'transactional_email_token_cleanup_failed', correlationId: corrId, humanId, action, error: cleanupError instanceof Error ? cleanupError.message : String(cleanupError) }));
    }
    throw error;
  }
}
