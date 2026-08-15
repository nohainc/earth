export type GameDeadline = {
  gameDay: number;
  gameMinute: number;
  realSecondsRemaining: number;
  closesAt: string;
};

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
}): GameDeadline | null {
  const closesAtMs = input.closesAt instanceof Date
    ? input.closesAt.getTime()
    : new Date(String(input.closesAt ?? '')).getTime();
  const secondsPerGameMinute = input.realSecondsPerGameMinute ?? 1;
  if (!Number.isFinite(closesAtMs) || !Number.isFinite(secondsPerGameMinute) || secondsPerGameMinute <= 0) return null;
  const realSecondsRemaining = Math.max(0, Math.ceil((closesAtMs - input.nowMs) / 1000));
  const gameMinutesRemaining = Math.floor(realSecondsRemaining / secondsPerGameMinute);
  const absoluteMinute = Math.max(0, input.gameDay * 1440 + input.gameMinute + gameMinutesRemaining);
  return {
    gameDay: Math.floor(absoluteMinute / 1440),
    gameMinute: absoluteMinute % 1440,
    realSecondsRemaining,
    closesAt: new Date(closesAtMs).toISOString(),
  };
}
