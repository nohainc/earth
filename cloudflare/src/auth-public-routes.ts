import { bytesToBase64, derivePassword, digest, validTotp } from './auth-crypto';
import { cookieValue, extractToken, issueActionToken, sessionCookie } from './auth-session';
import { registerIdentity, loginIdentity } from './auth-postgres';
import { parseJsonBody } from './request-validation';
import { withRepository } from './repository';

export async function publicAuthRoute(request: Request, env: Env, url: URL): Promise<Response | null> {
  if (url.pathname === '/api/auth/register' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ email?: string; password?: string; passwordConfirmation?: string; personName?: string; houseSurname?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const email = body.email?.trim().toLowerCase();
    const personName = body.personName?.trim();
    const houseSurname = body.houseSurname?.trim();
    const password = body.password ?? '';
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return Response.json({ ok: false, error: 'A valid email is required' }, { status: 400 });
    if (!personName || personName.length < 2 || personName.length > 40) return Response.json({ ok: false, error: 'Given name must be 2–40 characters' }, { status: 400 });
    if (!houseSurname || houseSurname.length < 2 || houseSurname.length > 40) return Response.json({ ok: false, error: 'House surname must be 2–40 characters' }, { status: 400 });
    if (password.length < 12) return Response.json({ ok: false, error: 'Password must be at least 12 characters' }, { status: 400 });
    if (password !== (body.passwordConfirmation ?? '')) return Response.json({ ok: false, error: 'Passwords do not match' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => registerIdentity(repository, { email, personName, houseSurname, password }));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      try {
        const identity = result.human as { id: string; email: string };
        await issueActionToken(env, identity.id, 'verify_email', identity.email);
      } catch {
        return Response.json({
          ...result,
          verificationPending: true,
          verificationDelivery: 'unavailable',
          message: 'Identity created. We could not send the verification email yet; use “Resend verification email” to try again.',
          persistence: 'planetscale-postgres',
        }, { status: 201 });
      }
      return Response.json({ ...result, verificationPending: true, persistence: 'planetscale-postgres' }, { status: 201 });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Identity creation failed';
      return Response.json({ ok: false, error: message }, { status: /already registered/i.test(message) ? 409 : 400 });
    }
  }
  if (url.pathname === '/api/auth/verify-email/resend' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ email?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = request.headers.get('x-correlation-id') || crypto.randomUUID();
    const email = parsed.value.email?.trim().toLowerCase();
    if (email) {
      const credential = (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string; email_verified_at: string | null }>('SELECT human_id, email, email_verified_at FROM auth_credentials WHERE email = $1', [email])))?.rows[0];
      if (credential && !credential.email_verified_at) {
        const recentlySent = (await withRepository(env, (repository) => repository.query('SELECT 1 FROM auth_action_tokens WHERE human_id = $1 AND action = \'verify_email\' AND created_at > CURRENT_TIMESTAMP - INTERVAL \'60 seconds\' LIMIT 1', [credential.human_id])))?.rows[0];
        if (!recentlySent) {
          try { await issueActionToken(env, credential.human_id, 'verify_email', credential.email, correlationId); } catch { return Response.json({ ok: false, error: 'The verification email could not be sent. Please try again shortly.' }, { status: 503, headers: { 'x-correlation-id': correlationId } }); }
        }
      }
    }
    return Response.json(
      { ok: true, message: 'If that identity exists and needs verification, a new email has been sent. Please wait at least 60 seconds before requesting another email.', cooldownSeconds: 60 },
      { headers: { 'x-correlation-id': correlationId } },
    );
  }
  if (url.pathname === '/api/auth/verify-email' && request.method === 'GET') {
    const token = url.searchParams.get('token');
    if (!token) return Response.json({ ok: false, error: 'Verification token is required' }, { status: 400 });
    const tokenHash = await digest(token);
    const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'verify_email' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
    if (!action) return Response.json({ ok: false, error: 'Verification link is invalid or expired' }, { status: 400 });
    const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
      await tx.query('UPDATE auth_credentials SET email_verified_at = CURRENT_TIMESTAMP WHERE human_id = $1', [action.human_id]);
      await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
      return true;
    }));
    if (!updated) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: true, message: 'Email verified. You can now sign in.' });
  }
  if (url.pathname === '/api/auth/password-reset/request' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ email?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const correlationId = request.headers.get('x-correlation-id') || crypto.randomUUID();
    const email = parsed.value.email?.trim().toLowerCase();
    const credential = email ? (await withRepository(env, (repository) => repository.query<{ human_id: string; email: string }>('SELECT human_id, email FROM auth_credentials WHERE email = $1', [email])))?.rows[0] : null;
    if (credential) {
      try {
        await issueActionToken(env, credential.human_id, 'reset_password', credential.email, correlationId);
      } catch {
        /* Keep recovery responses generic for security while logging with correlation ID. */
      }
    }
    return Response.json(
      {
        ok: true,
        message: 'If that identity exists, recovery instructions have been sent. Please wait at least 60 seconds before requesting another reset.',
        cooldownSeconds: 60,
      },
      { headers: { 'x-correlation-id': correlationId } },
    );
  }
  if (url.pathname === '/api/auth/password-reset/complete' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ token?: string; password?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!body.token || (body.password ?? '').length < 12) return Response.json({ ok: false, error: 'A valid token and 12-character password are required' }, { status: 400 });
    const tokenHash = await digest(body.token);
    const action = (await withRepository(env, (repository) => repository.query<{ id: string; human_id: string }>("SELECT id, human_id FROM auth_action_tokens WHERE token_hash = $1 AND action = 'reset_password' AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP", [tokenHash])))?.rows[0];
    if (!action) return Response.json({ ok: false, error: 'Recovery link is invalid or expired' }, { status: 400 });
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const passwordHash = await derivePassword(body.password, salt, 100000);
    const updated = await withRepository(env, (repository) => repository.transaction(async (tx) => {
      await tx.query('UPDATE auth_credentials SET password_hash = $1, password_salt = $2, password_iterations = $3 WHERE human_id = $4', [passwordHash, bytesToBase64(salt), 100000, action.human_id]);
      await tx.query('UPDATE auth_action_tokens SET consumed_at = CURRENT_TIMESTAMP WHERE id = $1', [action.id]);
      await tx.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [action.human_id]);
      return true;
    }));
    if (!updated) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: true, message: 'Password reset. All previous sessions were revoked.' });
  }
  if (url.pathname === '/api/auth/login' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ email?: string; password?: string; otp?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const email = parsed.value.email?.trim().toLowerCase();
    if (!email || !parsed.value.password) return Response.json({ ok: false, error: 'Invalid email or password' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => loginIdentity(repository, { email, password: parsed.value.password ?? '', otp: parsed.value.otp ?? '', validTotp }));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return new Response(JSON.stringify({ ok: result.ok, token: result.token, human: result.human, expiresAt: result.expiresAt }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(String(result.token), Number(result.maxAge)) } });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Invalid email or password';
      return Response.json({ ok: false, error: message }, { status: /too many/i.test(message) ? 429 : /verify|active/i.test(message) ? 403 : 401 });
    }
  }
  if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
    const token = extractToken(request);
    if (token) await withRepository(env, async (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = $1', [await digest(token)]));
    return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
  }
  return null;
}

export function isPublicAuthMutation(pathname: string): boolean {
  return pathname === '/api/auth/register' || pathname === '/api/auth/login' || pathname === '/api/auth/logout' || pathname === '/api/auth/verify-email/resend' || pathname === '/api/auth/password-reset/request' || pathname === '/api/auth/password-reset/complete';
}
