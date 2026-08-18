import test from 'node:test';
import assert from 'node:assert/strict';
import {
  listAccessibleChannels,
  listChannelMessages,
  sendChannelMessage,
  listDiplomaticDispatches,
  sendDiplomaticDispatch,
  markDispatchRead,
  getCommunicationsMetrics,
} from '../cloudflare/src/communications-postgres.ts';

test('communications domain logic handles channels, messages, dispatches, and unread counts', async () => {
  const channelStore = [
    { id: 'channel-global-relay', scope: 'global', scope_id: null, name: 'Planetary Public Relay', description: 'Universal relay' },
    { id: 'channel-city-new-tokyo', scope: 'city', scope_id: 'city-new-tokyo', name: 'Neo-Tokyo City Hall', description: 'Municipal forum' },
    { id: 'channel-city-london', scope: 'city', scope_id: 'city-london', name: 'London Forum', description: 'London forum' },
  ];

  const messagesStore = [];
  const dispatchesStore = [];

  const mockRepo = {
    async query(sql, params) {
      if (sql.includes('FROM comm_channels') && sql.includes('SELECT COUNT')) {
        return { rows: [{ count: channelStore.length }] };
      }
      if (sql.includes('FROM comm_channels')) {
        const cityId = params[0];
        const humanId = params[1];
        const rows = channelStore.filter((c) => c.scope === 'global' || (c.scope === 'city' && (!cityId || c.scope_id === cityId)));
        return { rows };
      }
      if (sql.includes('INSERT INTO comm_messages')) {
        const msg = {
          id: params[0],
          channel_id: params[1],
          sender_human_id: params[2],
          sender_display_name: params[3],
          sender_dynasty_name: params[4],
          body: params[5],
          game_day: params[6],
          game_minute: params[7],
          attachments: JSON.parse(params[8]),
          created_at: new Date().toISOString(),
        };
        messagesStore.push(msg);
        return { rows: [msg] };
      }
      if (sql.includes('FROM comm_messages')) {
        const channelId = params[0];
        const rows = messagesStore.filter((m) => m.channel_id === channelId);
        return { rows };
      }
      if (sql.includes('INSERT INTO diplomatic_dispatches')) {
        const dispatch = {
          id: params[0],
          sender_human_id: params[1],
          recipient_human_id: params[2],
          subject: params[3],
          body: params[4],
          status: 'unread',
          game_day: params[5],
          game_minute: params[6],
          dispatch_type: params[7],
          action_payload: JSON.parse(params[8]),
          created_at: new Date().toISOString(),
          read_at: null,
        };
        dispatchesStore.push(dispatch);
        return { rows: [dispatch] };
      }
      if (sql.includes('FROM diplomatic_dispatches') && sql.includes('COUNT(*)')) {
        const recipient = params[0];
        const unread = dispatchesStore.filter((d) => d.recipient_human_id === recipient && d.status === 'unread').length;
        return { rows: [{ count: unread }] };
      }
      if (sql.includes('FROM diplomatic_dispatches')) {
        const recipient = params[0];
        const rows = dispatchesStore.filter((d) => d.recipient_human_id === recipient);
        return { rows };
      }
      if (sql.includes('UPDATE diplomatic_dispatches')) {
        const id = params[0];
        const recipient = params[1];
        const found = dispatchesStore.find((d) => d.id === id && d.recipient_human_id === recipient);
        if (found) {
          found.status = 'read';
          found.read_at = new Date().toISOString();
        }
        return { rowCount: 1 };
      }
      return { rows: [] };
    },
  };

  // 1. List channels
  const channels = await listAccessibleChannels(mockRepo, 'H-0044', 'city-new-tokyo');
  assert.equal(channels.length, 2); // global + new tokyo

  // 2. Send message
  const msg = await sendChannelMessage(
    mockRepo,
    'H-0044',
    'Amara Vance',
    'Vance Dynasty',
    'channel-global-relay',
    'Broadcasting test signal',
    184,
    500,
    [{ type: 'contract', id: 'CTR-101' }]
  );
  assert.equal(msg.sender_display_name, 'Amara Vance');
  assert.equal(msg.body, 'Broadcasting test signal');
  assert.equal(msg.attachments.length, 1);

  // 3. List messages
  const msgs = await listChannelMessages(mockRepo, 'channel-global-relay');
  assert.equal(msgs.length, 1);
  assert.equal(msgs[0].id, msg.id);

  // 4. Send diplomatic dispatch
  const dispatch = await sendDiplomaticDispatch(
    mockRepo,
    'H-0012',
    'H-0044',
    'Bilateral Trade Terms',
    'We propose to exchange 200 circuit units.',
    'contract_offer',
    { contractId: 'CTR-900', credits: 1200 },
    184,
    520
  );
  assert.equal(dispatch.subject, 'Bilateral Trade Terms');
  assert.equal(dispatch.status, 'unread');

  // 5. List dispatches
  const inbox = await listDiplomaticDispatches(mockRepo, 'H-0044', 'inbox');
  assert.equal(inbox.dispatches.length, 1);
  assert.equal(inbox.unreadCount, 1);

  // 6. Metrics
  const metrics = await getCommunicationsMetrics(mockRepo, 'H-0044');
  assert.equal(metrics.unreadDispatches, 1);

  // 7. Mark read
  await markDispatchRead(mockRepo, 'H-0044', dispatch.id);
  assert.equal(dispatchesStore[0].status, 'read');
});
