import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const newsRead = read('cloudflare/src/read-models/news-read.ts');
const panel = read('flutter_client/lib/features/communications/news_panel.dart');
const dashboard = read('flutter_client/lib/features/command_center/dashboard.dart');
const formatters = read('flutter_client/lib/shared/widgets/format_helpers.dart');

test('News reads only explicit publications and has no Territory route', () => {
  assert.match(newsRead, /FROM news_publications/);
  assert.doesNotMatch(newsRead, /FROM notifications/);
  assert.doesNotMatch(newsRead, /THEN 'territories'/);
});

test('News UI owns only the V5 publication projection', () => {
  assert.doesNotMatch(panel, /final List<dynamic> events/);
  assert.doesNotMatch(panel, /final List<dynamic> notifications/);
  assert.doesNotMatch(panel, /location_city_outlined|amberAccent|TERRITORY/);
  assert.doesNotMatch(panel, /related_entity_id/);
  assert.match(panel, /formatGameMinute\(/);
  const newsCase = dashboard.slice(dashboard.indexOf("case 'news':"), dashboard.indexOf("case 'constitution':"));
  assert.doesNotMatch(newsCase, /events: events|notifications: notifications/);
});

test('Game-minute formatting is a zero-padded player-facing clock', () => {
  assert.match(formatters, /String formatGameMinute\(int gameMinute\)/);
  assert.match(formatters, /hour\.toString\(\)\.padLeft\(2, '0'\)/);
  assert.match(formatters, /minute\.toString\(\)\.padLeft\(2, '0'\)/);
});
