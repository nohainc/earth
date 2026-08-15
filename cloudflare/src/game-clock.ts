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
  deadlineGameDay?: number;
  deadlineGameMinute?: number;
}): GameDeadline | null {
  const secondsPerGameMinute = input.realSecondsPerGameMinute ?? 60;
  if (!Number.isFinite(secondsPerGameMinute) || secondsPerGameMinute <= 0) return null;
  if (Number.isFinite(input.deadlineGameDay) && Number.isFinite(input.deadlineGameMinute)) {
    const currentAbsoluteMinute = Math.max(0, Math.floor(input.gameDay * 1440 + input.gameMinute));
    const deadlineAbsoluteMinute = Math.max(0, Math.floor(Number(input.deadlineGameDay) * 1440 + Number(input.deadlineGameMinute)));
    const gameMinutesRemaining = Math.max(0, deadlineAbsoluteMinute - currentAbsoluteMinute);
    return {
      gameDay: Math.floor(deadlineAbsoluteMinute / 1440),
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
  const absoluteMinute = Math.max(0, input.gameDay * 1440 + input.gameMinute + gameMinutesRemaining);
  return {
    gameDay: Math.floor(absoluteMinute / 1440),
    gameMinute: absoluteMinute % 1440,
    realSecondsRemaining,
    closesAt: new Date(closesAtMs).toISOString(),
  };
}
