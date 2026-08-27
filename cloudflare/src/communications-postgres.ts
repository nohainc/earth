import type { PostgresRepository } from './repository.ts';

export interface CommChannel {
  id: string;
  scope: 'global' | 'city' | 'institution' | 'direct';
  scope_id: string | null;
  name: string;
  description: string | null;
  unread_count?: number;
}

export interface CommMessage {
  id: string;
  channel_id: string;
  sender_human_id: string;
  sender_display_name: string;
  sender_house_name: string | null;
  sender_dynasty_name?: string | null;
  body: string;
  game_day: number;
  game_minute: number;
  attachments: unknown[];
  created_at: string;
}

export interface DiplomaticDispatch {
  id: string;
  sender_human_id: string;
  sender_display_name?: string;
  sender_house_name?: string;
  sender_dynasty_name?: string;
  recipient_human_id: string;
  recipient_display_name?: string;
  subject: string;
  body: string;
  status: 'unread' | 'read' | 'archived';
  game_day: number;
  game_minute: number;
  dispatch_type: 'diplomatic' | 'contract_offer' | 'patent_license' | 'merger_tender' | 'succession_notice';
  action_payload: Record<string, unknown>;
  created_at: string;
  read_at: string | null;
}

export async function listAccessibleChannels(
  repository: PostgresRepository,
  humanId: string,
  cityId?: string | null
): Promise<CommChannel[]> {
  const sql = `
    SELECT id, scope, scope_id, name, description
    FROM comm_channels
    WHERE scope = 'global'
       OR (scope = 'city' AND (scope_id = $1 OR $1 IS NULL))
       OR (scope = 'direct' AND id LIKE '%' || $2 || '%')
    ORDER BY CASE scope WHEN 'global' THEN 1 WHEN 'city' THEN 2 WHEN 'institution' THEN 3 ELSE 4 END, name ASC
  `;
  const res = await repository.query<CommChannel>(sql, [cityId ?? null, humanId]);
  return res.rows;
}

export async function listChannelMessages(
  repository: PostgresRepository,
  channelId: string,
  limit = 50
): Promise<CommMessage[]> {
  const boundedLimit = Math.min(100, Math.max(1, limit));
  const sql = `
    SELECT id, channel_id, sender_human_id, sender_display_name, sender_house_name, sender_house_name AS sender_dynasty_name,
           body, game_day, game_minute, attachments, created_at
    FROM comm_messages
    WHERE channel_id = $1
    ORDER BY game_day ASC, created_at ASC
    LIMIT $2
  `;
  const res = await repository.query<CommMessage>(sql, [channelId, boundedLimit]);
  return res.rows;
}

export async function sendChannelMessage(
  repository: PostgresRepository,
  senderHumanId: string,
  senderDisplayName: string,
  senderHouseName: string | null,
  channelId: string,
  body: string,
  gameDay: number,
  gameMinute: number,
  attachments: unknown[] = [],
  correlationId = crypto.randomUUID()
): Promise<CommMessage> {
  const msgId = `msg-${correlationId}`;
  return repository.transaction(async (tx) => {
    const sql = `
    INSERT INTO comm_messages (id, channel_id, sender_human_id, sender_display_name, sender_house_name, body, game_day, game_minute, attachments)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (id) DO NOTHING
    RETURNING id, channel_id, sender_human_id, sender_display_name, sender_house_name, sender_house_name AS sender_dynasty_name, body, game_day, game_minute, attachments, created_at
  `;
    const res = await tx.query<CommMessage>(sql, [
    msgId,
    channelId,
    senderHumanId,
    senderDisplayName,
    senderHouseName,
    body,
    gameDay,
    gameMinute,
    JSON.stringify(attachments),
    ]);
    if (res.rows[0]) return res.rows[0];
    const replay = await tx.query<CommMessage>(
      `SELECT id, channel_id, sender_human_id, sender_display_name, sender_house_name, sender_house_name AS sender_dynasty_name, body, game_day, game_minute, attachments, created_at FROM comm_messages WHERE id = $1`,
      [msgId]
    );
    return replay.rows[0];
  });
}

export async function listDiplomaticDispatches(
  repository: PostgresRepository,
  humanId: string,
  folder: 'inbox' | 'sent' | 'archived' = 'inbox',
  limit = 30,
  offset = 0
): Promise<{ dispatches: DiplomaticDispatch[]; unreadCount: number }> {
  const boundedLimit = Math.min(100, Math.max(1, limit));
  const boundedOffset = Math.max(0, offset);

  let filterClause = '';
  const params: unknown[] = [humanId];

  if (folder === 'inbox') {
    filterClause = `d.recipient_human_id = $1 AND d.status IN ('unread', 'read')`;
  } else if (folder === 'sent') {
    filterClause = `d.sender_human_id = $1`;
  } else {
    filterClause = `d.recipient_human_id = $1 AND d.status = 'archived'`;
  }

  const sql = `
    SELECT d.id, d.sender_human_id, d.recipient_human_id, d.subject, d.body,
           d.status, d.game_day, d.game_minute, d.dispatch_type, d.action_payload,
           d.created_at, d.read_at,
           sh.display_name AS sender_display_name,
           sd.house_name AS sender_house_name,
           sd.house_name AS sender_dynasty_name,
           rh.display_name AS recipient_display_name
    FROM diplomatic_dispatches d
    LEFT JOIN humans sh ON sh.id = d.sender_human_id
    LEFT JOIN houses sd ON sd.founder_human_id = sh.id
    LEFT JOIN humans rh ON rh.id = d.recipient_human_id
    WHERE ${filterClause}
    ORDER BY d.game_day DESC, d.created_at DESC
    LIMIT $2 OFFSET $3
  `;

  params.push(boundedLimit, boundedOffset);

  const [dispatchesRes, unreadRes] = await Promise.all([
    repository.query<DiplomaticDispatch>(sql, params),
    repository.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM diplomatic_dispatches WHERE recipient_human_id = $1 AND status = 'unread'`,
      [humanId]
    ),
  ]);

  return {
    dispatches: dispatchesRes.rows,
    unreadCount: unreadRes.rows[0]?.count ?? 0,
  };
}

export async function sendDiplomaticDispatch(
  repository: PostgresRepository,
  senderHumanId: string,
  recipientHumanId: string,
  subject: string,
  body: string,
  dispatchType: 'diplomatic' | 'contract_offer' | 'patent_license' | 'merger_tender' | 'succession_notice' = 'diplomatic',
  actionPayload: Record<string, unknown> = {},
  gameDay = 1,
  gameMinute = 0,
  correlationId = crypto.randomUUID()
): Promise<DiplomaticDispatch> {
  const dispatchId = `mail-${correlationId}`;
  return repository.transaction(async (tx) => {
    const sql = `
    INSERT INTO diplomatic_dispatches (id, sender_human_id, recipient_human_id, subject, body, status, game_day, game_minute, dispatch_type, action_payload)
    VALUES ($1, $2, $3, $4, $5, 'unread', $6, $7, $8, $9)
    ON CONFLICT (id) DO NOTHING
    RETURNING id, sender_human_id, recipient_human_id, subject, body, status, game_day, game_minute, dispatch_type, action_payload, created_at, read_at
  `;
    const res = await tx.query<DiplomaticDispatch>(sql, [
    dispatchId,
    senderHumanId,
    recipientHumanId,
    subject,
    body,
    gameDay,
    gameMinute,
    dispatchType,
    JSON.stringify(actionPayload),
    ]);
    if (res.rows[0]) return res.rows[0];
    const replay = await tx.query<DiplomaticDispatch>(
      `SELECT id, sender_human_id, recipient_human_id, subject, body, status, game_day, game_minute, dispatch_type, action_payload, created_at, read_at FROM diplomatic_dispatches WHERE id = $1`,
      [dispatchId]
    );
    return replay.rows[0];
  });
}

export async function markDispatchRead(
  repository: PostgresRepository,
  humanId: string,
  dispatchId: string
): Promise<boolean> {
  return repository.transaction(async (tx) => {
    const sql = `
    UPDATE diplomatic_dispatches
    SET status = 'read', read_at = NOW()
    WHERE id = $1 AND recipient_human_id = $2 AND status = 'unread'
  `;
    await tx.query(sql, [dispatchId, humanId]);
    return true;
  });
}

export async function getCommunicationsMetrics(
  repository: PostgresRepository,
  humanId: string
): Promise<{ unreadDispatches: number; activeChannelsCount: number }> {
  const [unreadRes, channelsRes] = await Promise.all([
    repository.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM diplomatic_dispatches WHERE recipient_human_id = $1 AND status = 'unread'`,
      [humanId]
    ).catch(() => ({ rows: [{ count: 0 }] })),
    repository.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM comm_channels WHERE scope = 'global'`,
      []
    ).catch(() => ({ rows: [{ count: 1 }] })),
  ]);

  return {
    unreadDispatches: unreadRes.rows[0]?.count ?? 0,
    activeChannelsCount: channelsRes.rows[0]?.count ?? 1,
  };
}
