import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/read-models/news-read.ts', 'utf8');
const panel = fs.readFileSync('flutter_client/lib/features/communications/news_panel.dart', 'utf8');

test('News is a server-owned, cursor-paginated publication contract', () => {
  assert.match(source, /listNews/);
  assert.match(source, /ROW_NUMBER\(\) OVER/);
  assert.match(source, /correlation_id/);
  assert.match(source, /nextCursor/);
  assert.match(source, /related_route/);
  assert.match(source, /is_new/);
});

test('News presentation consumes canonical scope and topic metadata', () => {
  assert.match(panel, /item\['scope'\]/);
  assert.match(panel, /item\['topic'\]/);
  assert.match(panel, /item\['is_new'\]/);
  assert.doesNotMatch(panel, /notificationNewsCategory/);
  assert.doesNotMatch(panel, /contains\('research'\)/);
});
