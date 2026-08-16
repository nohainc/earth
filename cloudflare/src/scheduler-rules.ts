export function validateWorldAdvanceMinutes(minutesPerTick: number): void {
  if (!Number.isInteger(minutesPerTick) || minutesPerTick < 1 || minutesPerTick > 1440) {
    throw new Error('World advancement must be between 1 and 1,440 game minutes');
  }
}
