import test from 'node:test';
import assert from 'node:assert/strict';
import { listAccessibleChannels, listChannelMessages, sendChannelMessage, getCommunicationsMetrics } from '../cloudflare/src/communications-postgres.ts';

test('communications domain logic handles channels and messages', async () => {
  const channels = [
    { id: 'channel-global-relay', scope: 'global', scope_id: null, name: 'Planetary Public Relay', description: 'Universal relay' },
    { id: 'channel-city-new-tokyo', scope: 'city', scope_id: 'city-new-tokyo', name: 'Neo-Tokyo City Hall', description: 'Municipal forum' },
  ];
  const messages = [];
  const repo = {
    async query(sql, params) {
      if (sql.includes('COUNT(*)')) return { rows: [{ count: channels.length }] };
      if (sql.includes('SELECT EXISTS')) return { rows: [{ allowed: params[1] === 'H-0044' && (params[0] === 'channel-global-relay' || params[0] === 'channel-city-new-tokyo') }] };
      if (sql.includes('FROM comm_channels')) return { rows: channels };
      if (sql.includes('INSERT INTO comm_messages')) {
        const message = { id: params[0], channel_id: params[1], sender_human_id: params[2], sender_display_name: params[3], body: params[5], game_day: params[6], game_minute: params[7], attachments: JSON.parse(params[8]) };
        messages.push(message);
        return { rows: [message] };
      }
      if (sql.includes('FROM comm_messages')) return { rows: messages.filter((m) => m.channel_id === params[0]) };
      return { rows: [] };
    },
  };
  repo.transaction = async (work) => work(repo);

  assert.equal((await listAccessibleChannels(repo, 'H-0044')).length, 2);
  const message = await sendChannelMessage(repo, 'H-0044', 'Amara Vance', 'House of Vance', 'channel-global-relay', 'Broadcasting test signal', 184, 500, []);
  assert.equal(message.body, 'Broadcasting test signal');
  assert.equal((await listChannelMessages(repo, 'H-0044', 'channel-global-relay')).length, 1);
  const metrics = await getCommunicationsMetrics(repo, 'H-0044');
  assert.equal(metrics.activeChannelsCount, 2);
});
