import type { PostgresRepository } from './repository.ts';

export interface AppErrorLogInput {
  humanId?: string | null;
  source: 'backend_api' | 'client_flutter' | 'scheduler';
  endpoint?: string | null;
  statusCode?: number | null;
  errorCode?: string | null;
  errorMessage: string;
  stackTrace?: string | null;
  contextData?: Record<string, unknown> | null;
}

export interface AppErrorLogRow {
  id: string;
  created_at: string;
  human_id: string | null;
  source: string;
  endpoint: string | null;
  status_code: number | null;
  error_code: string | null;
  error_message: string;
  stack_trace: string | null;
  context_data: Record<string, unknown>;
}

export async function logAppError(
  repository: PostgresRepository,
  input: AppErrorLogInput,
): Promise<{ id: string }> {
  const id = crypto.randomUUID();
  const res = await repository.query<{ id: string }>(
    `INSERT INTO app_error_logs (
       id, human_id, source, endpoint, status_code, error_code, error_message, stack_trace, context_data, created_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
     RETURNING id`,
    [
      id,
      input.humanId ?? null,
      input.source,
      input.endpoint ?? null,
      input.statusCode ?? null,
      input.errorCode ?? null,
      input.errorMessage ? input.errorMessage.slice(0, 4000) : 'Unknown error',
      input.stackTrace ? input.stackTrace.slice(0, 10000) : null,
      JSON.stringify(input.contextData ?? {}),
    ],
  );
  return { id: res.rows[0]?.id ?? id };
}

export async function listRecentAppErrors(
  repository: PostgresRepository,
  options?: { limit?: number; offset?: number; humanId?: string; source?: string },
): Promise<AppErrorLogRow[]> {
  const limit = Math.min(100, Math.max(1, options?.limit ?? 50));
  const offset = Math.max(0, options?.offset ?? 0);
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (options?.humanId) {
    params.push(options.humanId);
    conditions.push(`human_id = $${params.length}`);
  }
  if (options?.source) {
    params.push(options.source);
    conditions.push(`source = $${params.length}`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  params.push(limit);
  params.push(offset);

  const res = await repository.query<AppErrorLogRow>(
    `SELECT id, created_at, human_id, source, endpoint, status_code, error_code, error_message, stack_trace, context_data
     FROM app_error_logs
     ${whereClause}
     ORDER BY created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  return res.rows;
}
