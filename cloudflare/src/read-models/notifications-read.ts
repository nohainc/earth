import type { PostgresRepository } from '../repository.ts';

export async function listNotifications(repository: PostgresRepository, houseId: string, limit: number): Promise<Record<string, unknown>> {
  const [notifications, unread] = await Promise.all([
    repository.query('SELECT id, notification_type, title, body, entity_type, entity_id, game_day, game_minute, read_at, created_at FROM notifications WHERE house_id = $1 ORDER BY created_at DESC LIMIT $2', [houseId, limit]),
    repository.query<{ count: string }>('SELECT COUNT(*)::integer AS count FROM notifications WHERE house_id = $1 AND read_at IS NULL', [houseId]),
  ]);
  return { notifications: notifications.rows, unread: Number(unread.rows[0]?.count ?? 0) };
}

export async function markNotificationRead(repository: PostgresRepository, houseId: string, notificationId: string): Promise<Record<string, unknown>> {
  await repository.query('UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE id = $1 AND house_id = $2', [notificationId, houseId]);
  return { ok: true };
}

export async function markAllNotificationsRead(repository: PostgresRepository, houseId: string): Promise<Record<string, unknown>> {
  await repository.query('UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE house_id = $1 AND read_at IS NULL', [houseId]);
  return { ok: true, unread: 0, unreadCount: 0 };
}
