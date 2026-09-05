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
  return extractTokens(request)[0] ?? null;
}

export function extractTokens(request: Request): string[] {
  // The Flutter client deliberately sends the current bearer token while a
  // browser may still carry an older HttpOnly cookie from a previous session.
  // Prefer the explicit Authorization credential so a stale cookie cannot
  // override a freshly issued login token. Cookies remain the fallback for
  // browser clients that do not send a bearer token.
  const authHeader = request.headers.get('Authorization') ?? request.headers.get('authorization');
  if (authHeader && /^Bearer\s+/i.test(authHeader)) {
    const bearer = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (bearer) {
      const cookieTok = cookieValue(request, 'earth_session');
      return cookieTok && cookieTok !== bearer ? [bearer, cookieTok] : [bearer];
    }
  }
  const cookieTok = cookieValue(request, 'earth_session');
  return cookieTok ? [cookieTok] : [];
}
