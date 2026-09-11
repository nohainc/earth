export const GAME_DAY_MINUTES = 1_440;

export type GamePosition = { gameDay: number; gameMinute: number };

/** Day 1, minute 0 is absolute minute 0. This is the only market time conversion. */
export function absoluteGameMinute(gameDay: number, gameMinute: number): number {
  if (!Number.isInteger(gameDay) || gameDay < 1) throw new Error('gameDay must be a positive integer');
  if (!Number.isInteger(gameMinute) || gameMinute < 0 || gameMinute >= GAME_DAY_MINUTES) {
    throw new Error(`gameMinute must be between 0 and ${GAME_DAY_MINUTES - 1}`);
  }
  return (gameDay - 1) * GAME_DAY_MINUTES + gameMinute;
}

export function gamePosition(totalMinutes: number): GamePosition {
  if (!Number.isInteger(totalMinutes) || totalMinutes < 0) throw new Error('totalMinutes must be a non-negative integer');
  return {
    gameDay: Math.floor(totalMinutes / GAME_DAY_MINUTES) + 1,
    gameMinute: totalMinutes % GAME_DAY_MINUTES,
  };
}

export function marketBatchId(gameDay: number, gameMinute: number, batchDurationMinutes: number): number {
  if (!Number.isInteger(batchDurationMinutes) || batchDurationMinutes < 1) {
    throw new Error('batchDurationMinutes must be a positive integer');
  }
  return Math.floor(absoluteGameMinute(gameDay, gameMinute) / batchDurationMinutes);
}

export function marketBatchRange(batchId: number, batchDurationMinutes: number): { startMinute: number; endMinute: number } {
  if (!Number.isInteger(batchId) || batchId < 0) throw new Error('batchId must be a non-negative integer');
  if (!Number.isInteger(batchDurationMinutes) || batchDurationMinutes < 1) {
    throw new Error('batchDurationMinutes must be a positive integer');
  }
  const startMinute = batchId * batchDurationMinutes;
  return { startMinute, endMinute: startMinute + batchDurationMinutes };
}
