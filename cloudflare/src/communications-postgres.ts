import type { PostgresRepository } from './repository.ts';
import { toNanoMarkup } from './nano-markup.ts';

export interface CommChannel {
  id: string;
  scope: 'global' | 'city' | 'corporation' | 'community' | 'direct';
  scope_id: string | null;
  name: string;
  description: string | null;
  unread_count?: number;
}

export interface CommMessage {
  id: string;
  channel_id: string;
  sender_house_id: string;
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

export async function listAccessibleChannels(
  repository: PostgresRepository,
  humanId: string
): Promise<CommChannel[]> {
  const sql = `
    SELECT ch.id, ch.scope, ch.scope_id,
           CASE WHEN ch.scope = 'direct' THEN COALESCE(other.display_name, ch.name) ELSE ch.name END AS name,
           ch.description,
           latest.body AS latest_message,
           latest.created_at AS latest_message_at
    FROM comm_channels ch
    LEFT JOIN comm_direct_conversations direct ON direct.channel_id = ch.id
    LEFT JOIN houses other_house ON other_house.id = CASE
      WHEN direct.participant_low_house_id = (SELECT house_id FROM humans WHERE id = $1) THEN direct.participant_high_house_id
      ELSE direct.participant_low_house_id
    END
    LEFT JOIN humans other ON other.id = other_house.current_human_id
    LEFT JOIN LATERAL (
      SELECT body, created_at FROM comm_messages
      WHERE channel_id = ch.id ORDER BY created_at DESC LIMIT 1
    ) latest ON TRUE
    WHERE ch.scope = 'global'
       OR (ch.scope = 'city' AND EXISTS (
            SELECT 1 FROM house_affiliations ha
             WHERE ha.house_id = (SELECT house_id FROM humans WHERE id = $1) AND ha.status = 'ACTIVE' AND ha.city_id = ch.scope_id))
       OR (ch.scope = 'corporation' AND EXISTS (
            SELECT 1 FROM house_affiliations ha
             WHERE ha.house_id = (SELECT house_id FROM humans WHERE id = $1) AND ha.status = 'ACTIVE' AND ha.corporation_id = ch.scope_id))
       OR FALSE /* Community membership awaits a House-based Communities V2 model. */
       OR (ch.scope = 'direct' AND EXISTS (
            SELECT 1 FROM comm_direct_conversations d
            WHERE d.channel_id = ch.id AND (SELECT house_id FROM humans WHERE id = $1) IN (d.participant_low_house_id, d.participant_high_house_id)))
    ORDER BY CASE ch.scope
      WHEN 'corporation' THEN 1 WHEN 'city' THEN 2 WHEN 'community' THEN 3
      WHEN 'direct' THEN 4 WHEN 'global' THEN 5 ELSE 6 END,
      latest.created_at DESC NULLS LAST, name ASC
  `;
  const res = await repository.query<CommChannel>(sql, [humanId]);
  return res.rows;
}

export async function listChannelMessages(
  repository: PostgresRepository,
  humanId: string,
  channelId: string,
  limit = 50
): Promise<CommMessage[]> {
  if (!(await canAccessChannel(repository, humanId, channelId))) return [];
  const boundedLimit = Math.min(100, Math.max(1, limit));
  const sql = `
    SELECT id, channel_id, sender_house_id, sender_human_id, sender_display_name, sender_dynasty_name AS sender_house_name, sender_dynasty_name,
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
    if (!(await canAccessChannel(tx, senderHumanId, channelId))) {
      throw new Error('You do not have access to this channel');
    }
    const sender = await tx.query<{ house_id: string }>('SELECT house_id FROM humans WHERE id = $1 AND status = \'ACTIVE\'', [senderHumanId]);
    if (!sender.rows[0]) throw new Error('Active Human is required to send messages');
    const sql = `
    INSERT INTO comm_messages (id, channel_id, sender_house_id, sender_human_id, sender_display_name, sender_dynasty_name, body, game_day, game_minute, attachments)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    ON CONFLICT (id) DO NOTHING
    RETURNING id, channel_id, sender_house_id, sender_human_id, sender_display_name, sender_dynasty_name AS sender_house_name, sender_dynasty_name, body, game_day, game_minute, attachments, created_at
  `;
    const res = await tx.query<CommMessage>(sql, [
    msgId, channelId, sender.rows[0].house_id, senderHumanId, senderDisplayName,
    senderHouseName, body, gameDay, gameMinute,
    toNanoMarkup(attachments),
    ]);
    if (res.rows[0]) return res.rows[0];
    const replay = await tx.query<CommMessage>(
      `SELECT id, channel_id, sender_house_id, sender_human_id, sender_display_name, sender_dynasty_name AS sender_house_name, sender_dynasty_name, body, game_day, game_minute, attachments, created_at FROM comm_messages WHERE id = $1`,
      [msgId]
    );
    return replay.rows[0];
  });
}

export async function canAccessChannel(
  repository: PostgresRepository,
  humanId: string,
  channelId: string,
): Promise<boolean> {
  const result = await repository.query<{ allowed: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM comm_channels ch
       WHERE ch.id = $1 AND (
         ch.scope = 'global'
         OR (ch.scope = 'city' AND EXISTS (SELECT 1 FROM house_affiliations ha WHERE ha.house_id = (SELECT house_id FROM humans WHERE id = $2) AND ha.status = 'ACTIVE' AND ha.city_id = ch.scope_id))
         OR (ch.scope = 'corporation' AND EXISTS (SELECT 1 FROM house_affiliations ha WHERE ha.house_id = (SELECT house_id FROM humans WHERE id = $2) AND ha.status = 'ACTIVE' AND ha.corporation_id = ch.scope_id))
         OR FALSE /* Community membership awaits a House-based Communities V2 model. */
       OR (ch.scope = 'direct' AND EXISTS (SELECT 1 FROM comm_direct_conversations d WHERE d.channel_id = ch.id AND (SELECT house_id FROM humans WHERE id = $2) IN (d.participant_low_house_id, d.participant_high_house_id)))
       )
     ) AS allowed`,
    [channelId, humanId],
  );
  return Boolean(result.rows[0]?.allowed);
}

export async function openDirectConversation(
  repository: PostgresRepository,
  humanId: string,
  targetHumanId: string,
  correlationId = crypto.randomUUID(),
): Promise<CommChannel> {
  if (humanId === targetHumanId) throw new Error('You cannot message yourself');
  return repository.transaction(async (tx) => {
    const target = await tx.query<{ house_id: string }>(
      `SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'`,
      [targetHumanId],
    );
    if (!target.rows[0]) throw new Error('The selected user is not available');
    const source = await tx.query<{ house_id: string }>(
      `SELECT house_id FROM humans WHERE id = $1 AND status = 'ACTIVE'`, [humanId],
    );
    if (!source.rows[0]) throw new Error('Active Human is required to open a conversation');
    if (source.rows[0].house_id === target.rows[0].house_id) {
      throw new Error('Both Humans belong to the same House');
    }
    const [low, high] = [source.rows[0].house_id, target.rows[0].house_id].sort();
    const existing = await tx.query<CommChannel>(
      `SELECT ch.id, ch.scope, ch.scope_id, other.display_name AS name, ch.description
       FROM comm_direct_conversations d
       JOIN comm_channels ch ON ch.id = d.channel_id
       JOIN houses other_house ON other_house.id = CASE WHEN d.participant_low_house_id = $1 THEN d.participant_high_house_id ELSE d.participant_low_house_id END
       JOIN humans other ON other.id = other_house.current_human_id
       WHERE d.participant_low_house_id = $1 AND d.participant_high_house_id = $2`,
      [low, high],
    );
    if (existing.rows[0]) return existing.rows[0];
    const channelId = `channel-direct-${low}-${high}`;
    await tx.query(
      `INSERT INTO comm_channels (id, scope, scope_id, name, description)
       VALUES ($1, 'direct', NULL, 'Private conversation', 'Private conversation between two active users')
       ON CONFLICT (id) DO NOTHING`,
      [channelId],
    );
    await tx.query(
      `INSERT INTO comm_direct_conversations (channel_id, participant_low_house_id, participant_high_house_id)
       VALUES ($1, $2, $3) ON CONFLICT (participant_low_house_id, participant_high_house_id) DO NOTHING`,
      [channelId, low, high],
    );
    const created = await tx.query<CommChannel>(
      `SELECT ch.id, ch.scope, ch.scope_id, other.display_name AS name, ch.description
       FROM comm_direct_conversations d JOIN comm_channels ch ON ch.id = d.channel_id
       JOIN houses other_house ON other_house.id = CASE WHEN d.participant_low_house_id = $1 THEN d.participant_high_house_id ELSE d.participant_low_house_id END
       JOIN humans other ON other.id = other_house.current_human_id
       WHERE d.participant_low_house_id = $1 AND d.participant_high_house_id = $2`,
      [low, high],
    );
    return created.rows[0];
  });
}

export async function getCommunicationsMetrics(
  repository: PostgresRepository,
  _humanId: string
): Promise<{ activeChannelsCount: number }> {
  const channelsRes = await repository.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count FROM comm_channels WHERE scope = 'global'`,
      []
    );

  return {
    activeChannelsCount: channelsRes.rows[0]?.count ?? 0,
  };
}
