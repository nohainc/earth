export function maintenanceModeEnabled(env: unknown): boolean {
  const value = (env as Record<string, unknown> | null | undefined)?.EARTH_MAINTENANCE_MODE;
  return ['1', 'true', 'yes', 'on', 'enabled'].includes(String(value ?? '').trim().toLowerCase());
}

export function schedulerEnabled(env: unknown): boolean {
  const value = (env as Record<string, unknown> | null | undefined)?.EARTH_SCHEDULER_ENABLED;
  return !['0', 'false', 'no', 'off', 'disabled'].includes(String(value ?? 'true').trim().toLowerCase());
}

export function maintenanceResponse(): Response {
  return Response.json(
    { ok: false, error: 'EARTH is temporarily unavailable for scheduled maintenance', code: 'MAINTENANCE_MODE' },
    { status: 503, headers: { 'Retry-After': '60', 'Cache-Control': 'no-store' } },
  );
}
