import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { listSocialDirectory } from '../cloudflare/src/social-directory-postgres.ts';

test('neutral social directory only queries active people and entities', async () => {
  const calls = [];
  const repository = new PostgresRepository({
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [], rowCount: 0 };
    },
  });

  const directory = await listSocialDirectory(repository, 'H-1', 'Ada');

  assert.deepEqual(directory, { humans: [], businesses: [], cities: [], corporations: [], communities: [] });
  assert.equal(calls.length, 4);
  assert.ok(calls.every(({ sql }) => !/social_initiatives|social_relationships|social_initiative_members/i.test(sql)));
  assert.match(calls[0].sql, /h\.life_status = 'active'/);
});
