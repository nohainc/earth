type LogValue = string | number | boolean | null;

const SECRET_KEY = /(token|secret|password|cookie|authorization|credential|api[_-]?key)/i;
const MAX_MESSAGE = 4000;
const MAX_STACK = 10000;
const MAX_CONTEXT_KEYS = 40;

function safeValue(value: unknown, depth = 0): unknown {
  if (depth > 2) return '[truncated]';
  if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  if (Array.isArray(value)) return value.slice(0, 20).map((item) => safeValue(item, depth + 1));
  if (typeof value !== 'object') return String(value);
  const result: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>).slice(0, MAX_CONTEXT_KEYS)) {
    result[key] = SECRET_KEY.test(key) ? '[redacted]' : safeValue(item, depth + 1);
  }
  return result;
}

export type ClientErrorInput = {
  requestId?: string | null;
  humanId?: string | null;
  endpoint?: string | null;
  statusCode?: number | null;
  errorCode?: string | null;
  message?: string | null;
  stack?: string | null;
  context?: Record<string, unknown> | null;
  clientVersion?: string | null;
};

export function logClientError(input: ClientErrorInput): void {
  console.error(JSON.stringify({
    event: 'client_error',
    severity: 'error',
    requestId: input.requestId ?? null,
    humanId: input.humanId ?? null,
    source: 'client_flutter',
    endpoint: input.endpoint ?? null,
    statusCode: input.statusCode ?? null,
    errorCode: input.errorCode ?? null,
    message: String(input.message ?? 'Client error').slice(0, MAX_MESSAGE),
    stack: input.stack ? String(input.stack).slice(0, MAX_STACK) : null,
    context: safeValue(input.context ?? {}),
    clientVersion: input.clientVersion ?? null,
    at: new Date().toISOString(),
  }));
}

export function logBackendError(input: Omit<ClientErrorInput, 'context'> & { source?: 'backend_api' | 'scheduler' }): void {
  console.error(JSON.stringify({
    event: input.source === 'scheduler' ? 'scheduler_error' : 'backend_error',
    severity: 'error',
    requestId: input.requestId ?? null,
    humanId: input.humanId ?? null,
    source: input.source ?? 'backend_api',
    endpoint: input.endpoint ?? null,
    statusCode: input.statusCode ?? 500,
    errorCode: input.errorCode ?? 'INTERNAL_ERROR',
    message: String(input.message ?? 'Internal Server Error').slice(0, MAX_MESSAGE),
    stack: input.stack ? String(input.stack).slice(0, MAX_STACK) : null,
    at: new Date().toISOString(),
  }));
}

export function logBackendDiagnostic(error: unknown, input: { requestId?: string | null; endpoint?: string | null; correlationId?: string | null } = {}): void {
  const value = error && typeof error === 'object' ? error as Record<string, unknown> : {};
  const message = error instanceof Error ? error.message : typeof error === 'object' ? JSON.stringify(error) : String(error);
  console.error(JSON.stringify({
    event: 'postgres_error',
    severity: 'error',
    requestId: input.requestId ?? null,
    correlationId: input.correlationId ?? null,
    endpoint: input.endpoint ?? null,
    code: value.code ?? null,
    constraint: value.constraint ?? null,
    detail: value.detail ?? null,
    diagnostic: message.slice(0, MAX_MESSAGE),
    stack: error instanceof Error ? error.stack?.slice(0, MAX_STACK) : null,
    at: new Date().toISOString(),
  }));
}

export function sanitizeClientContext(context: unknown): Record<string, unknown> {
  const value = safeValue(context);
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
