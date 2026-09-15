import type { PostgresRepository } from './repository.ts';

export type NotificationInput = {
  id: string;
  houseId?: string;
  humanId: string;
  notificationType: string;
  title: string;
  body: string;
  entityType?: string | null;
  entityId?: string | null;
  gameDay?: number | null;
  gameMinute?: number | null;
  correlationId?: string | null;
};

/** Write one House-owned notification while retaining the originating Human for audit. */
// @mutation-boundary caller-owned-transaction: notification writes are part of the originating mutation.
export async function createNotification(repository: PostgresRepository, input: NotificationInput): Promise<void> {
  await repository.query(
    `INSERT INTO notifications
      (id, house_id, human_id, notification_type, title, body, entity_type, entity_id,
       game_day, game_minute, correlation_id)
     SELECT $1, COALESCE($2, h.house_id), $3, $4, $5, $6, $7, $8, $9, $10, $11
       FROM humans h
      WHERE h.id = $3
     ON CONFLICT (correlation_id) DO NOTHING`,
    [input.id, input.houseId ?? null, input.humanId, input.notificationType, input.title, input.body,
      input.entityType ?? null, input.entityId ?? null, input.gameDay ?? null, input.gameMinute ?? null,
      input.correlationId ?? input.id],
  );
}
