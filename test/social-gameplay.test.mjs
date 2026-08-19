import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { listSocialDirectory, listSocialInitiatives } from '../cloudflare/src/social-gameplay-postgres.ts';
import { createSocialInitiative, contributeToSocialInitiative, respondToSocialInitiative } from '../cloudflare/src/social-gameplay-postgres.ts';
import { generateDecisionQueue } from '../cloudflare/src/decision-queue.ts';

class MockClient {
  constructor() { this.calls = []; }
  async query(sql, params = []) {
    this.calls.push({ sql, params });
    if (sql.includes('FROM humans')) return { rows: [{ id: 'H-2', display_name: 'Ari', standing: 12 }], rowCount: 1 };
    if (sql.includes('FROM social_initiatives')) return { rows: [{ id: 'social-1', title: 'Trade Compact', status: 'proposed', member_status: 'invited' }], rowCount: 1 };
    return { rows: [], rowCount: 0 };
  }
}

test('social directory exposes public humans without account ownership data', async () => {
  const client = new MockClient();
  const directory = await listSocialDirectory(new PostgresRepository(client), 'H-1', 'Ari');
  assert.equal(directory.humans[0].display_name, 'Ari');
  assert.equal('owner_id' in directory.humans[0], false);
});

test('social initiatives become actionable decision queue items', () => {
  const queue = generateDecisionQueue({ social: [{ id: 'social-1', title: 'Trade Compact', status: 'proposed', member_status: 'invited', deadline_game_day: 190 }] });
  const item = queue.find((entry) => entry.category === 'social');
  assert.ok(item);
  assert.equal(item.targetSection, 'activity');
});

test('social initiatives are scoped to the current human', async () => {
  const client = new MockClient();
  const initiatives = await listSocialInitiatives(new PostgresRepository(client), 'H-1');
  assert.equal(initiatives[0].id, 'social-1');
  assert.ok(client.calls[0].params.includes('H-1'));
});

test('social timeline query scopes events through initiative visibility', async () => {
  const client = new MockClient();
  const { listSocialTimeline } = await import('../cloudflare/src/social-gameplay-postgres.ts');
  await listSocialTimeline(new PostgresRepository(client), 'H-1');
  assert.match(client.calls.at(-1).sql, /social_initiative_members/);
  assert.match(client.calls.at(-1).sql, /creator_human_id/);
});

test('social terms reject unsafe deadlines and credit values before touching the database', async () => {
  const repo = new PostgresRepository(new MockClient());
  await assert.rejects(() => createSocialInitiative(repo, { creatorId: 'H-1', targetId: 'H-2', kind: 'agreement', title: 'Bad', body: 'Bad', gameDay: 10, terms: { creditAmount: -1, deadlineGameDay: 11 } }), /Credit amount/);
  await assert.rejects(() => createSocialInitiative(repo, { creatorId: 'H-1', targetId: 'H-2', kind: 'agreement', title: 'Bad', body: 'Bad', gameDay: 10, terms: { deadlineGameDay: 10 } }), /Deadline/);
});

test('lifecycle actions reject invalid contribution bounds', async () => {
  const repo = new PostgresRepository(new MockClient());
  await assert.rejects(() => contributeToSocialInitiative(repo, 'H-1', 'social-1', 0), /integer from 1 to 100/);
  await assert.rejects(() => contributeToSocialInitiative(repo, 'H-1', 'social-1', 101), /integer from 1 to 100/);
});
