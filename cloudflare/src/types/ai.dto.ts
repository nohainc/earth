export interface AssistantDTO { id: string; tier: 'basic' | 'business'; policy: 'recommend' | 'maintenance'; enabled: boolean; }
export interface DecisionQueueItemDTO { id: string; title: string; urgency?: 'high' | 'medium' | 'low'; targetSection?: string; }
export interface ObjectiveDTO { id: string; title: string; progressPercentage: number; status: 'in_progress' | 'completed' | 'claimed'; }
