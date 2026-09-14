import type { PostgresRepository } from './repository.ts';
import { toNanoMarkup } from './nano-markup.ts';

export type GameEventInput = {
  id: string;
  category: string;
  eventType: string;
  gameDay: number;
  gameMinute?: number | null;
  actorHouseId?: string | null;
  actorHumanId?: string | null;
  institutionId?: string | null;
  subjectType?: string | null;
  subjectId?: string | null;
  title: string;
  details?: unknown;
  correlationId?: string | null;
};

export async function createGameEvent(repository: PostgresRepository, input: GameEventInput): Promise<void> {
  await repository.query(
    `INSERT INTO game_events
      (id, category, event_type, game_day, game_minute, actor_house_id, actor_human_id,
       institution_id, subject_type, subject_id, title, details, correlation_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
     ON CONFLICT DO NOTHING`,
    [input.id, input.category, input.eventType, input.gameDay, input.gameMinute ?? null,
      input.actorHouseId ?? null, input.actorHumanId ?? null, input.institutionId ?? null,
      input.subjectType ?? null, input.subjectId ?? null, input.title,
      typeof input.details === 'string' ? input.details : toNanoMarkup(input.details ?? {}), input.correlationId ?? input.id],
  );
}

export async function createAffiliationEvent(
  repository: PostgresRepository,
  input: { id: string; humanId: string; institutionType: 'CORPORATION'; institutionId: string; action: string; gameDay: number; reason: string },
): Promise<void> {
  await createGameEvent(repository, {
    id: input.id,
    category: 'AFFILIATION',
    eventType: `HOUSE_${input.action}_${input.institutionType}`.toUpperCase(),
    gameDay: input.gameDay,
    actorHumanId: input.humanId,
    subjectType: input.institutionType,
    subjectId: input.institutionId,
    title: `${input.institutionType} affiliation ${input.action}`,
    details: { humanId: input.humanId, institutionId: input.institutionId, reason: input.reason },
  });
}
