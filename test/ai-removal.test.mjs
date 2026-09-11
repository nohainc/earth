import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('AI Assistant runtime, schema and client surfaces are removed', () => {
  const manifest = JSON.parse(read('db/schema-manifest.json'));
  const schema = read('db/schema.sql');
  const index = read('cloudflare/src/index.ts');
  const world = read('cloudflare/src/world-postgres.ts');
  const state = read('flutter_client/lib/core/models/earth_state.dart');
  const api = read('flutter_client/lib/core/api/earth_api_technology.dart');

  assert.equal(fs.existsSync(path.join(root, 'cloudflare/src/ai-postgres.ts')), false);
  assert.equal(fs.existsSync(path.join(root, 'cloudflare/src/ai-routes.ts')), false);
  assert.equal(fs.existsSync(path.join(root, 'flutter_client/lib/features/operations/ai_panel.dart')), false);
  assert.equal(manifest.requiredTables.ai_assistants, undefined);
  assert.equal(manifest.requiredTables.ai_recommendation_feedback, undefined);
  assert.doesNotMatch(schema, /CREATE TABLE IF NOT EXISTS ai_/i);
  assert.doesNotMatch(index, /ai-postgres|ai-routes|\/api\/ai/i);
  assert.doesNotMatch(world, /ai_assistants|aiAssistants|aiRecommendations/i);
  assert.doesNotMatch(state, /aiAssistants|aiRecommendations/i);
  assert.doesNotMatch(api, /setAiPolicy|upgradeAi|\/api\/ai/i);
});

test('AI removal migration preserves generic communications', () => {
  const migration = read('db/migrations/339_remove_ai_assistant.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /DROP TABLE IF EXISTS ai_recommendation_feedback/);
  assert.match(migration, /DROP TABLE IF EXISTS ai_assistants/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS comm_channels/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS comm_messages/);
  assert.doesNotMatch(schema, /AI Advisory/i);
});
