import test from 'node:test';
import assert from 'node:assert/strict';
import { setOrganizationVotingSettings } from '../cloudflare/src/governance-v4-postgres.ts';
import { amendOrganizationCharter } from '../cloudflare/src/organization-charter-postgres.ts';

test('retired direct voting-setting service fails closed before touching persistence', async () => {
  let queries = 0;
  const repository = { query: async () => { queries += 1; return { rows: [] }; } };
  await assert.rejects(
    setOrganizationVotingSettings(repository, {
      organizationId: 'CORP-1',
      humanId: 'HUMAN-1',
      votingMethod: 'ONE_HOUSE_ONE_VOTE',
      correlationId: 'boundary-vote-1',
    }),
    /Direct voting-setting mutation is retired/,
  );
  assert.equal(queries, 0);
});

test('retired direct charter service fails closed before touching persistence', async () => {
  let queries = 0;
  const repository = { query: async () => { queries += 1; return { rows: [] }; } };
  await assert.rejects(
    amendOrganizationCharter(repository, {
      organizationId: 'CORP-1',
      houseId: 'HOUSE-1',
      humanId: 'HUMAN-1',
      charter: {},
      correlationId: 'boundary-charter-1',
    }),
    /Direct Charter mutation is retired/,
  );
  assert.equal(queries, 0);
});
