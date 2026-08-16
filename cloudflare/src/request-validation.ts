const MAX_JSON_BODY_BYTES = 64 * 1024;

export function resolveIdempotencyKey(request: Request,
    bodyCorrelationId?: string): string | null {
  const header = request.headers.get('Idempotency-Key')?.trim() || '';
  const body = bodyCorrelationId?.trim() || '';
  if (header && body && header !== body) return null;
  const value = header || body || crypto.randomUUID();
  return value.length > 160 ? null : value;
}

function validationResponse(request: Request, error: string, status: number): Response {
  return Response.json({
    ok: false,
    error,
    code: status === 413 ? 'PAYLOAD_TOO_LARGE' : 'VALIDATION_ERROR',
    correlationId: request.headers.get('X-Request-ID') ?? crypto.randomUUID(),
  }, { status });
}

export type JsonBodyResult<T> =
  | { ok: true; value: T }
  | { ok: false; response: Response };

export async function parseJsonBody<T>(request: Request, maxBytes = MAX_JSON_BODY_BYTES): Promise<JsonBodyResult<T>> {
  const declaredLength = Number(request.headers.get('Content-Length') ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return { ok: false, response: validationResponse(request, `Request body must be ${maxBytes} bytes or smaller`, 413) };
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    return { ok: false, response: validationResponse(request, `Request body must be ${maxBytes} bytes or smaller`, 413) };
  }

  if (!text.trim()) return { ok: true, value: {} as T };
  try {
    const value: unknown = JSON.parse(text);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('JSON body must be an object');
    return { ok: true, value: value as T };
  } catch {
    return { ok: false, response: validationResponse(request, 'Request body must be valid JSON object', 400) };
  }
}
