import { bytesToBase32, validTotp, digest } from './auth-crypto';
import { cookieValue, extractToken, currentHuman, sessionCookie } from './auth-session';
import { parseJsonBody } from './request-validation';
import { withRepository } from './repository';
import { rebornIdentity, claimHeirIdentity } from './auth-postgres';

export async function authenticatedAuthRoute(request: Request, env: Env, url: URL): Promise<Response | null> {
  if (url.pathname === '/api/auth/me' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    return Response.json({ authenticated: Boolean(human), human, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/auth/mfa/enroll' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const secret = bytesToBase32(crypto.getRandomValues(new Uint8Array(20)));
    const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_secret = $1, mfa_enabled = false WHERE human_id = $2', [secret, human.id]));
    if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: true, secret, otpauth: `otpauth://totp/EARTH:${encodeURIComponent(human.email)}?secret=${secret}&issuer=EARTH`, message: 'Scan or enter this secret in an authenticator, then confirm with a six-digit code.' });
  }
  if (url.pathname === '/api/auth/mfa/confirm' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ code?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null }>('SELECT mfa_secret FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
    if (!credential?.mfa_secret || !(await validTotp(credential.mfa_secret, parsed.value.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
    const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = true WHERE human_id = $1', [human.id]));
    if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: true, enabled: true });
  }
  if (url.pathname === '/api/auth/mfa/disable' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ code?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const credential = (await withRepository(env, (repository) => repository.query<{ mfa_secret: string | null; mfa_enabled: boolean }>('SELECT mfa_secret, mfa_enabled FROM auth_credentials WHERE human_id = $1', [human.id])))?.rows[0];
    if (!credential?.mfa_enabled || !credential.mfa_secret || !(await validTotp(credential.mfa_secret, parsed.value.code ?? ''))) return Response.json({ ok: false, error: 'Invalid authenticator code' }, { status: 400 });
    const result = await withRepository(env, (repository) => repository.query('UPDATE auth_credentials SET mfa_enabled = false, mfa_secret = NULL WHERE human_id = $1', [human.id]));
    if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: true, enabled: false });
  }
  if (url.pathname === '/api/auth/sessions' && request.method === 'GET') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const token = extractToken(request);
    const currentHash = token ? await digest(token) : '';
    const sessions = await withRepository(env, (repository) => repository.query('SELECT id, created_at, expires_at, revoked_at, token_hash FROM auth_sessions WHERE human_id = $1 ORDER BY created_at DESC', [human.id]));
    if (!sessions) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ sessions: sessions.rows.map(({ token_hash: _tokenHash, ...session }) => ({ ...session, current: _tokenHash === currentHash })), persistence: 'planetscale-postgres' });
  }
  const revokeSessionMatch = url.pathname.match(/^\/api\/auth\/sessions\/([^/]+)$/);
  if (revokeSessionMatch && request.method === 'DELETE') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1 AND human_id = $2 AND revoked_at IS NULL', [revokeSessionMatch[1], human.id]));
    if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return Response.json({ ok: result.rowCount === 1, persistence: 'planetscale-postgres' });
  }
  if (url.pathname === '/api/auth/sessions' && request.method === 'DELETE') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => repository.query('UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE human_id = $1 AND revoked_at IS NULL', [human.id]));
    if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
    return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie('', 0) } });
  }
  if (url.pathname === '/api/auth/rebirth' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ displayName?: string; dynastyName?: string; startingCityId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const displayName = parsed.value.displayName?.trim();
    if (!displayName || displayName.length < 2 || displayName.length > 80) return Response.json({ ok: false, error: 'Display name must be 2–80 characters' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) => rebornIdentity(repository, { email: human.email, displayName, dynastyName: parsed.value.dynastyName?.trim(), startingCityId: parsed.value.startingCityId }));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return new Response(JSON.stringify(result), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(String(result.token), Number(result.maxAge)) } });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Rebirth transaction failed';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }
  if (url.pathname === '/api/auth/claim-heir' && request.method === 'POST') {
    const human = await currentHuman(request, env);
    if (!human) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    try {
      const result = await withRepository(env, (repository) => claimHeirIdentity(repository, { email: human.email }));
      if (!result) return Response.json({ ok: false, error: 'Authentication storage is unavailable' }, { status: 503 });
      return new Response(JSON.stringify(result), { headers: { 'content-type': 'application/json', 'Set-Cookie': sessionCookie(String(result.token), Number(result.maxAge)) } });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Succession claim failed';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }
  return null;
}
