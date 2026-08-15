const MAX_JSON_BODY_BYTES = 64 * 1024;

export type JsonBodyResult<T> =
  | { ok: true; value: T }
  | { ok: false; response: Response };

export async function parseJsonBody<T>(request: Request, maxBytes = MAX_JSON_BODY_BYTES): Promise<JsonBodyResult<T>> {
  const declaredLength = Number(request.headers.get('Content-Length') ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return { ok: false, response: Response.json({ ok: false, error: `Request body must be ${maxBytes} bytes or smaller` }, { status: 413 }) };
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    return { ok: false, response: Response.json({ ok: false, error: `Request body must be ${maxBytes} bytes or smaller` }, { status: 413 }) };
  }

  if (!text.trim()) return { ok: true, value: {} as T };
  try {
    const value: unknown = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('JSON body must be an object');
    return { ok: true, value: value as T };
  } catch {
    return { ok: false, response: Response.json({ ok: false, error: 'Request body must be valid JSON object' }, { status: 400 }) };
  }
}
