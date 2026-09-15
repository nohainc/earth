export type BuildingAgeAssessment = { ageDays: bigint; designLifeDays: bigint; burdenMultiplierBps: bigint; overdueDays: bigint; operable: boolean };

export function assessBuildingAge(input: { currentGameDay: bigint; lastMajorRebuildGameDay: bigint; designLifeDays: bigint; overdueBurdenBpsPerDay: bigint; maximumBurdenBps: bigint }): BuildingAgeAssessment {
  if (input.designLifeDays <= 0n || input.maximumBurdenBps < 10000n) throw new Error('Invalid building design-life rule');
  const ageDays = input.currentGameDay >= input.lastMajorRebuildGameDay ? input.currentGameDay - input.lastMajorRebuildGameDay : 0n;
  const overdueDays = ageDays > input.designLifeDays ? ageDays - input.designLifeDays : 0n;
  const burdenMultiplierBps = overdueDays === 0n ? 10000n : input.maximumBurdenBps < 10000n + overdueDays * input.overdueBurdenBpsPerDay ? input.maximumBurdenBps : 10000n + overdueDays * input.overdueBurdenBpsPerDay;
  return { ageDays, designLifeDays: input.designLifeDays, burdenMultiplierBps, overdueDays, operable: true };
}
