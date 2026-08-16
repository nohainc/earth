import { bytesToBase32, validTotp, digest } from './auth-crypto';
import { cookieValue, currentHuman, sessionCookie } from './auth-session';
import { parseJsonBody } from './request-validation';
import { withRepository } from './repository';

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
    const token = cookieValue(request, 'earth_session');
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
  return null;
}
