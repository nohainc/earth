export const DEFAULT_GENESIS_START_ISO = '2026-01-01T00:00:00.000Z';

/**
 * Continuous time configuration:
 * 1 real-world second = 1 game minute.
 * 1 real-world hour = 60 game hours = 2.5 game days.
 * 1 real-world day = 60 game days (~2 game months).
 */
export const REAL_SECONDS_PER_GAME_MINUTE = 1;
export const REAL_MS_PER_GAME_MINUTE = REAL_SECONDS_PER_GAME_MINUTE * 1000;
export const REAL_MS_PER_GAME_DAY = 1440 * REAL_MS_PER_GAME_MINUTE;

export interface TimeDerivation {
  gameDay: number;
  gameMinute: number;
  fractionalGameDay: number;
  fractionalGameMinute: number;
  effectiveGenesisAt: string;
  simulatedDayOffset: number;
  elapsedRealMs: number;
}

export function getEffectiveGenesis(input?: {
  genesisAt?: Date | string | null;
  simulatedDayOffset?: number | null;
}): Date {
  const baseMs = input?.genesisAt instanceof Date
    ? input.genesisAt.getTime()
    : new Date(String(input?.genesisAt ?? DEFAULT_GENESIS_START_ISO)).getTime();
  const validBaseMs = Number.isFinite(baseMs) ? baseMs : new Date(DEFAULT_GENESIS_START_ISO).getTime();
  const offsetDays = Number.isFinite(input?.simulatedDayOffset) ? Number(input?.simulatedDayOffset) : 0;
  const offsetMs = offsetDays * REAL_MS_PER_GAME_DAY;
  return new Date(validBaseMs - offsetMs);
}

export function deriveContinuousGameTime(input?: {
  nowMs?: number | null;
  genesisAt?: Date | string | null;
  simulatedDayOffset?: number | null;
}): TimeDerivation {
  const effectiveGenesis = getEffectiveGenesis(input);
  const now = input?.nowMs != null && Number.isFinite(input.nowMs) ? input.nowMs : Date.now();
  const elapsedRealMs = Math.max(0, now - effectiveGenesis.getTime());
  const totalFractionalMinutes = elapsedRealMs / REAL_MS_PER_GAME_MINUTE;
  const fractionalGameDay = totalFractionalMinutes / 1440;
  const gameDay = Math.floor(fractionalGameDay);
  const gameMinute = Math.floor(totalFractionalMinutes % 1440);
  const fractionalGameMinute = totalFractionalMinutes % 1440;
  const offsetDays = Number.isFinite(input?.simulatedDayOffset) ? Number(input?.simulatedDayOffset) : 0;

  return {
    gameDay,
    gameMinute,
    fractionalGameDay,
    fractionalGameMinute,
    effectiveGenesisAt: effectiveGenesis.toISOString(),
    simulatedDayOffset: offsetDays,
    elapsedRealMs,
  };
}
