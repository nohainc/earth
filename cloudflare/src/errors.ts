import { logBackendDiagnostic } from './observability.ts';

export type EarthErrorCode =
  | 'VALIDATION_ERROR'
  | 'AUTHENTICATION_REQUIRED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'COMMUNITY_NAME_TAKEN'
  | 'COMMUNITY_ALREADY_MEMBER'
  | 'COMMUNITY_REQUEST_PENDING'
  | 'COMMUNITY_LAST_OWNER'
  | 'COMMUNITY_DISBANDED'
  | 'SERVICE_UNAVAILABLE'
  | 'INTERNAL_ERROR';

export class EarthDomainError extends Error {
  readonly code: EarthErrorCode;
  readonly status: number;
  readonly publicMessage: string;
  readonly details?: Record<string, unknown>;

  constructor(code: EarthErrorCode, publicMessage: string, status: number, details?: Record<string, unknown>) {
    super(publicMessage);
    this.name = 'EarthDomainError';
    this.code = code;
    this.status = status;
    this.publicMessage = publicMessage;
    this.details = details;
  }
}

const statuses: Record<EarthErrorCode, number> = {
  VALIDATION_ERROR: 400,
  AUTHENTICATION_REQUIRED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  COMMUNITY_NAME_TAKEN: 409,
  COMMUNITY_ALREADY_MEMBER: 409,
  COMMUNITY_REQUEST_PENDING: 409,
  COMMUNITY_LAST_OWNER: 409,
  COMMUNITY_DISBANDED: 409,
  SERVICE_UNAVAILABLE: 503,
  INTERNAL_ERROR: 500,
};

export function earthError(code: EarthErrorCode, publicMessage: string, details?: Record<string, unknown>): EarthDomainError {
  return new EarthDomainError(code, publicMessage, statuses[code], details);
}

type PostgresError = { code?: unknown; constraint?: unknown; detail?: unknown };

export function mapPostgresError(error: unknown): EarthDomainError | undefined {
  if (!error || typeof error !== 'object') return undefined;
  const postgres = error as PostgresError;
  if (
    postgres.code === '23505' &&
    ['communities_normalized_name_key', 'communities_active_normalized_name_uq'].includes(String(postgres.constraint))
  ) {
    return earthError('COMMUNITY_NAME_TAKEN', 'A community with this name already exists.', { field: 'name' });
  }
  if (postgres.code === '23505' && postgres.constraint === 'community_membership_requests_pending_uq') {
    return earthError('COMMUNITY_REQUEST_PENDING', 'A membership request is already pending.', { field: 'community' });
  }
  if (postgres.code === '40001' || postgres.code === '40P01') return earthError('CONFLICT', 'The operation conflicted with another update. Please try again.');
  if (postgres.code === '08000' || postgres.code === '08003' || postgres.code === '08006' || postgres.code === '57P01') return earthError('SERVICE_UNAVAILABLE', 'PostgreSQL persistence is unavailable.');
  return undefined;
}

export function toEarthError(error: unknown, fallbackCode: EarthErrorCode = 'INTERNAL_ERROR', fallbackMessage = 'The request could not be completed.'): EarthDomainError {
  if (error instanceof EarthDomainError) return error;
  return mapPostgresError(error) ?? earthError(fallbackCode, fallbackMessage);
}

import { isSettlementBarrierError, SettlementCatchupBarrierError } from './settlement-barrier-postgres.ts';

export function errorResponse(error: unknown, correlationId?: string, fallbackMessage = 'The request could not be completed.', context: { requestId?: string | null; endpoint?: string | null } = {}): Response {
  if (isSettlementBarrierError(error)) {
    return error.toResponse();
  }
  if (!(error instanceof EarthDomainError)) logBackendDiagnostic(error, { ...context, correlationId });
  const mapped = toEarthError(error, 'INTERNAL_ERROR', fallbackMessage);
  const body: Record<string, unknown> = { ok: false, code: mapped.code, error: mapped.publicMessage };
  if (correlationId) body.correlationId = correlationId;
  if (mapped.details) Object.assign(body, mapped.details);
  return Response.json(body, { status: mapped.status });
}

export const toApiErrorResponse = errorResponse;
