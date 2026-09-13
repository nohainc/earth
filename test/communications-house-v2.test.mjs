import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/001_baseline.sql', 'utf8');
const runtime = fs.readFileSync('cloudflare/src/communications-postgres.ts', 'utf8');

test('communications persist direct conversations by House and messages by House plus Human', () => {
  assert.match(migration, /participant_low_house_id\s+TEXT\s+NOT NULL/);
  assert.match(migration, /participant_high_house_id\s+TEXT\s+NOT NULL/);
  assert.match(migration, /sender_house_id\s+TEXT\s+NOT NULL/);
  assert.match(migration, /attachments\s+TEXT\s+NOT NULL/);
  assert.match(runtime, /participant_low_house_id/);
  assert.match(runtime, /sender_house_id/);
  assert.match(runtime, /house_affiliations/);
  assert.match(runtime, /toNanoMarkup\(attachments\)/);
  assert.doesNotMatch(runtime, /participant_low_id|participant_high_id/);
  assert.doesNotMatch(runtime, /\bFROM\s+memberships\b|\bJOIN\s+memberships\b/i);
  assert.doesNotMatch(runtime, /\bFROM\s+community_members\b|\bJOIN\s+community_members\b/i);
});

test('communications preserve House continuity while retaining Human sender attribution', () => {
  assert.match(runtime, /other_house\.current_human_id/);
  assert.match(runtime, /sender_human_id/);
  assert.match(runtime, /ON CONFLICT \(participant_low_house_id, participant_high_house_id\)/);
});
