export type GameDeadline = {
  gameDay: number;
  gameMinute: number;
  realSecondsRemaining: number;
  closesAt: string;
};

export const DEFAULT_GENESIS_START_ISO = '2026-01-01T00:00:00.000Z';

/**
 * Calculates the effective genesis start date taking into account any simulated days passed.
 * Shifting the effective genesis backward by the simulated day offset allows all game time
 * calculations to seamlessly derive the correct game day and minute.
 */
export function getEffectiveGenesisTime(input?: {
  genesisAt?: Date | string | null;
  simulatedDayOffset?: number | null;
}): Date {
  const baseMs = input?.genesisAt instanceof Date
    ? input.genesisAt.getTime()
    : new Date(String(input?.genesisAt ?? DEFAULT_GENESIS_START_ISO)).getTime();
  const validBaseMs = Number.isFinite(baseMs) ? baseMs : new Date(DEFAULT_GENESIS_START_ISO).getTime();
  const offsetDays = Number.isFinite(input?.simulatedDayOffset) ? Number(input?.simulatedDayOffset) : 0;
  // simulated_day_offset is measured in game days. At 1 real second per
  // game minute, one game day is 1,440 real seconds.
  const offsetMs = offsetDays * 1440 * 1000;
  return new Date(validBaseMs - offsetMs);
}

export type AuthoritativeGameTime = {
  totalGameMinutes: number;
  gameDay: number;
  gameMinute: number;
  effectiveGenesisAt: string;
  simulatedDayOffset: number;
};

/**
 * Authoritative single entry point to compute the current game day and minute.
 */
export function getAuthoritativeGameTime(input?: {
  nowMs?: number | null;
  genesisAt?: Date | string | null;
  simulatedDayOffset?: number | null;
}): AuthoritativeGameTime {
  const effectiveGenesis = getEffectiveGenesisTime(input);
  const now = input?.nowMs != null && Number.isFinite(input.nowMs) ? input.nowMs : Date.now();
  const elapsedMs = Math.max(0, now - effectiveGenesis.getTime());
  // The world clock runs at 1 real second = 1 game minute. Keep this
  // calculation in lockstep with the database function and the Flutter HUD.
  const totalGameMinutes = Math.floor(elapsedMs / 1000);
  const gameDay = Math.floor(totalGameMinutes / 1440) + 1;
  const gameMinute = totalGameMinutes % 1440;
  const offsetDays = Number.isFinite(input?.simulatedDayOffset) ? Number(input?.simulatedDayOffset) : 0;

  return {
    totalGameMinutes,
    gameDay,
    gameMinute,
    effectiveGenesisAt: effectiveGenesis.toISOString(),
    simulatedDayOffset: offsetDays,
  };
}

/**
 * Projects a real-time deadline onto the authoritative game clock for display.
 * It does not advance the world or make a gameplay decision.
 */
export function projectGameDeadline(input: {
  gameDay: number;
  gameMinute: number;
  closesAt: unknown;
  nowMs: number;
  realSecondsPerGameMinute?: number;
  deadlineGameDay?: number;
  deadlineGameMinute?: number;
}): GameDeadline | null {
  const secondsPerGameMinute = input.realSecondsPerGameMinute ?? 1;
  if (!Number.isFinite(secondsPerGameMinute) || secondsPerGameMinute <= 0) return null;
  if (Number.isFinite(input.deadlineGameDay) && Number.isFinite(input.deadlineGameMinute)) {
    const currentAbsoluteMinute = Math.max(0, Math.floor((Math.max(1, input.gameDay) - 1) * 1440 + input.gameMinute));
    const deadlineAbsoluteMinute = Math.max(0, Math.floor((Math.max(1, Number(input.deadlineGameDay)) - 1) * 1440 + Number(input.deadlineGameMinute)));
    const gameMinutesRemaining = Math.max(0, deadlineAbsoluteMinute - currentAbsoluteMinute);
    return {
      gameDay: Math.floor(deadlineAbsoluteMinute / 1440) + 1,
      gameMinute: deadlineAbsoluteMinute % 1440,
      realSecondsRemaining: Math.ceil(gameMinutesRemaining * secondsPerGameMinute),
      closesAt: new Date(input.nowMs + gameMinutesRemaining * secondsPerGameMinute * 1000).toISOString(),
    };
  }
  const closesAtMs = input.closesAt instanceof Date
    ? input.closesAt.getTime()
    : new Date(String(input.closesAt ?? '')).getTime();
  if (!Number.isFinite(closesAtMs)) return null;
  const realSecondsRemaining = Math.max(0, Math.ceil((closesAtMs - input.nowMs) / 1000));
  const gameMinutesRemaining = Math.floor(realSecondsRemaining / secondsPerGameMinute);
  const absoluteMinute = Math.max(0, (Math.max(1, input.gameDay) - 1) * 1440 + input.gameMinute + gameMinutesRemaining);
  return {
    gameDay: Math.floor(absoluteMinute / 1440) + 1,
    gameMinute: absoluteMinute % 1440,
    realSecondsRemaining,
    closesAt: new Date(closesAtMs).toISOString(),
  };
}
