export type GenerationState = { generationId: string; minimumGameDay: number; predecessorDiscovered: boolean; eligible: boolean; reason: string };

export function evaluateGeneration(input: { generationId: string; minimumGameDay: number; currentGameDay: number; predecessorId?: string | null; predecessorDiscovered: boolean; generationNumber?: number; earthFrontierGeneration?: number }): GenerationState {
  if (input.generationNumber !== undefined && input.earthFrontierGeneration !== undefined && input.generationNumber > input.earthFrontierGeneration) return { generationId: input.generationId, minimumGameDay: input.minimumGameDay, predecessorDiscovered: input.predecessorDiscovered, eligible: false, reason: 'earth_frontier_not_reached' };
  if (input.currentGameDay < input.minimumGameDay) return { generationId: input.generationId, minimumGameDay: input.minimumGameDay, predecessorDiscovered: input.predecessorDiscovered, eligible: false, reason: 'world_milestone_not_reached' };
  if (input.predecessorId && !input.predecessorDiscovered) return { generationId: input.generationId, minimumGameDay: input.minimumGameDay, predecessorDiscovered: false, eligible: false, reason: 'predecessor_not_discovered' };
  return { generationId: input.generationId, minimumGameDay: input.minimumGameDay, predecessorDiscovered: true, eligible: true, reason: 'eligible' };
}
