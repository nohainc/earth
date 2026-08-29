export interface HumanDTO { id: string; username?: string; life_status?: string; credits?: number; standing?: number; legacy?: number; }
export interface WorldSnapshotDTO { gameDay: number; gameMinute?: number; human?: HumanDTO; resources?: Record<string, number>; }
