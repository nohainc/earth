import type { DailySettlementPhase } from './daily-settlement-phases.ts';

export type SettlementWorkState = { phaseId: string; status: 'pending' | 'running' | 'completed' | 'failed'; shard: number };

export function canStartPhase(phase: DailySettlementPhase, work: readonly SettlementWorkState[]): boolean {
  return phase.prerequisites.every((id) => work.filter((item) => item.phaseId === id).every((item) => item.status === 'completed'));
}

export function settlementBarrier(phases: readonly DailySettlementPhase[], work: readonly SettlementWorkState[]) {
  const required = phases.filter((phase) => phase.status === 'required');
  const incomplete = required.filter((phase) => !canStartPhase(phase, work) || work.some((item) => item.phaseId === phase.id && item.status !== 'completed'));
  return { open: incomplete.length === 0, requiredPhaseCount: required.length, completedPhaseCount: required.length - incomplete.length, incompletePhaseIds: incomplete.map((phase) => phase.id) };
}
