export interface ProposalDTO { id: string; title?: string; status?: string; closes_game_day?: number; }
export interface VoteDTO { id: string; proposal_id: string; human_id?: string; choice?: string; weight?: number; }
