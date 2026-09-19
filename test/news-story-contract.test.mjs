import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { listNews } from '../cloudflare/src/read-models/news-read.ts';

const read = (path) => fs.readFileSync(path, 'utf8');
const server = read('cloudflare/src/read-models/news-read.ts');
const publication = read('cloudflare/src/news-publications-postgres.ts');
const migration = read('db/migrations/144_explicit_news_publications.sql');
const readStateMigration = read('db/migrations/145_house_news_read_state.sql');
const model = read('flutter_client/lib/core/models/news_story.dart');
const panel = read('flutter_client/lib/features/communications/news_panel.dart');
const routes = read('cloudflare/src/read-model-routes.ts');
const apiWorld = read('flutter_client/lib/core/api/earth_api_world.dart');
const commandCenter = read('flutter_client/lib/features/command_center/command_center_screen.dart');
const navigation = read('flutter_client/lib/core/navigation_registry.dart');
const formatters = read('flutter_client/lib/shared/widgets/format_helpers.dart');

test('News taxonomy is limited to V5 editorial scopes, topics, and importance', () => {
  assert.match(migration, /scope_type IN \('EARTH', 'CORPORATION', 'COMMUNITY'\)/);
  assert.match(migration, /topic IN \('GOVERNANCE', 'TECHNOLOGY', 'ECONOMY', 'INFRASTRUCTURE', 'SOCIETY', 'LIFECYCLE'\)/);
  assert.match(migration, /importance IN \('MAJOR', 'NOTABLE', 'ROUTINE'\)/);
  assert.match(publication, /NewsScopeType = 'EARTH' \| 'CORPORATION' \| 'COMMUNITY'/);
  assert.match(publication, /NewsTopic = 'GOVERNANCE'.*'LIFECYCLE'/s);
  assert.match(publication, /NewsImportance = 'MAJOR' \| 'NOTABLE' \| 'ROUTINE'/);
  assert.match(panel, /title: 'COMMUNITIES'/);
  assert.match(panel, /case 'COMMUNITY'/);
});

test('News filters are server-side and cursors retain their filter context', () => {
  assert.match(routes, /url\.searchParams\.get\('scope'\)/);
  assert.match(routes, /url\.searchParams\.get\('topic'\)/);
  assert.match(routes, /url\.searchParams\.get\('importance'\)/);
  assert.match(server, /cursor\.scope !== filters\.scope/);
  assert.match(server, /scope_type = \$6/);
  assert.match(server, /topic = \$7/);
  assert.match(server, /importance = \$8/);
  assert.match(server, /filters\.scope/);
  assert.match(apiWorld, /String\? scope/);
  assert.match(commandCenter, /api\.news\(scope: _newsScopeQuery\(\)\)/);
  assert.match(panel, /onScopeChanged/);
  assert.doesNotMatch(panel, /final String _filter/);
});

test('News API publishes one canonical typed story shape', () => {
  for (const field of ['id:', 'scope:', 'topic:', 'importance:', 'headline:', 'summary:', 'gameDay:', 'gameMinute:', 'relatedEntity:', 'action:', 'viewer:', 'publicationKey:']) {
    assert.match(server, new RegExp(`\\b${field.replace(':', '')}\\s*:`));
  }
  assert.match(server, /viewer: \{ isNew: row\.viewer_is_new === true \}/);
  assert.match(server, /publicationKey: String\(row\.publication_key\)/);
  assert.doesNotMatch(server, /news: items,/);
});

test('News publication is an explicit, idempotent public boundary', () => {
  assert.match(migration, /CREATE TABLE news_publications/);
  assert.match(migration, /publication_key TEXT NOT NULL UNIQUE/);
  assert.match(publication, /publishNewsStory/);
  assert.match(publication, /ON CONFLICT \(publication_key\) DO NOTHING/);
  assert.match(server, /FROM news_publications/);
  assert.doesNotMatch(server, /FROM notifications/);
  assert.doesNotMatch(server, /FROM game_events/);
});

test('News read model returns canonical nested publication data', async () => {
  const repository = {
    async query() {
      return { rows: [{
        news_id: 'PUB-1',
        publication_key: 'governance:proposal:1',
        scope: 'EARTH',
        topic: 'GOVERNANCE',
        importance: 'NOTABLE',
        game_day: 12,
        game_minute: 90,
        occurred_at: '2026-01-01T00:00:00Z',
        headline: 'Proposal passed',
        summary: 'A public proposal passed.',
        related_entity_type: 'PROPOSAL',
        related_entity_id: 'P-1',
        related_entity_name: 'Capacity policy',
        related_route: 'constitution',
        action_entity_id: 'P-1',
        action_label: 'VIEW GOVERNANCE',
        viewer_is_new: true,
      }] };
    },
  };
  const result = await listNews(repository, 'HOUSE-1', 25);
  assert.deepEqual(result.news[0], {
    id: 'PUB-1',
    scope: { type: 'EARTH' },
    topic: 'GOVERNANCE',
    importance: 'NOTABLE',
    headline: 'Proposal passed',
    summary: 'A public proposal passed.',
    gameDay: 12,
    gameMinute: 90,
    relatedEntity: { type: 'PROPOSAL', id: 'P-1', name: 'Capacity policy' },
    action: { route: 'constitution', entityId: 'P-1', label: 'VIEW GOVERNANCE' },
    viewer: { isNew: true },
    publicationKey: 'governance:proposal:1',
  });
});

test('News read state is independent from notification read_at', () => {
  assert.match(readStateMigration, /CREATE TABLE house_news_read_state/);
  assert.match(server, /LEFT JOIN house_news_read_state/);
  assert.match(server, /viewer_is_new/);
  assert.match(server, /export async function markNewsSeen/);
  assert.match(server, /ON CONFLICT \(house_id\) DO UPDATE/);
  assert.match(routes, /\/api\/news\/seen/);
  assert.match(apiWorld, /markNewsSeen/);
  assert.match(commandCenter, /api\.markNewsSeen\(newest\)/);
  assert.doesNotMatch(server, /read_at/);
});

test('News publication actions use only navigation-contract routes', () => {
  const mappedRoutes = [...publication.matchAll(/route: '([^']+)'/g)].map((match) => match[1]);
  const navigationRoutes = [
    ...[...navigation.matchAll(/canonicalRoute: '([^']+)'/g)].map((match) => match[1]),
    ...[...navigation.matchAll(/aliases: \[([^\]]*)\]/g)].flatMap((match) =>
      [...match[1].matchAll(/'([^']+)'/g)].map((alias) => alias[1])),
  ];
  assert.ok(mappedRoutes.length > 0);
  for (const route of mappedRoutes) {
    assert.ok(navigationRoutes.includes(route), `News route is not navigable: ${route}`);
  }
  assert.match(publication, /newsActionFor/);
  assert.doesNotMatch(publication, /actionRoute\?:/);
});

test('News regression boundaries exclude legacy scopes, routes, and notification sources', async () => {
  assert.doesNotMatch(publication, /TERRITORY|CITY|territories|city/i);
  assert.doesNotMatch(server, /TERRITORY|territories|FROM notifications|FROM game_events/i);
  assert.doesNotMatch(panel, /relatedEntity\.id|action\.entityId|entityId\)/);
  assert.match(panel, /formatGameMinute\(item\.gameMinute/);
  assert.doesNotMatch(server, /function actionLabel|notificationNewsCategory|classifyNews/);

  const publicRow = {
    news_id: 'PUB-CORP-1', publication_key: 'corporation:founded:1', scope: 'CORPORATION',
    topic: 'SOCIETY', importance: 'MAJOR', game_day: 4, game_minute: 450,
    occurred_at: '2026-01-01T00:00:00Z', headline: 'Nova founded', summary: 'A public corporation was founded.',
    related_entity_type: 'CORPORATION', related_entity_id: 'CORP-1', related_entity_name: 'Nova',
    related_route: 'corporations', action_entity_id: 'CORP-1', action_label: 'VIEW CORPORATIONS',
    viewer_is_new: false,
  };
  const repository = {
    async query(_sql, params) {
      return { rows: [{ ...publicRow, viewer_is_new: params?.[8] === 'HOUSE-NEW' }] };
    },
  };
  const firstHouse = await listNews(repository, 'HOUSE-OLD', 25, undefined, { scope: 'CORPORATION' });
  const secondHouse = await listNews(repository, 'HOUSE-NEW', 25, undefined, { scope: 'CORPORATION' });
  assert.deepEqual({ ...firstHouse.news[0], viewer: undefined }, { ...secondHouse.news[0], viewer: undefined });
  assert.equal(firstHouse.news[0].viewer.isNew, false);
  assert.equal(secondHouse.news[0].viewer.isNew, true);
  assert.equal(secondHouse.news[0].scope.type, 'CORPORATION');
  assert.equal(secondHouse.news[0].action.route, 'corporations');
});

test('News keeps lifecycle publications distinct by publication key', () => {
  assert.match(publication, /publicationKey: string/);
  assert.match(publication, /ON CONFLICT \(publication_key\) DO NOTHING/);
  assert.doesNotMatch(publication, /ON CONFLICT \(correlation_id\)/);
  assert.match(migration, /publication_key TEXT NOT NULL UNIQUE/);
  assert.match(formatters, /final hour = minuteOfDay ~\/ 60/);
  assert.match(formatters, /final minute = minuteOfDay % 60/);
  assert.match(formatters, /padLeft\(2, '0'\)/);
});

test('Flutter NewsStory parses canonical nested sections without legacy key fallbacks', () => {
  for (const field of ['class NewsStory', 'NewsScope', 'NewsRelatedEntity', 'NewsAction', 'NewsViewer', 'publicationKey']) {
    assert.match(model, new RegExp(field));
  }
  assert.doesNotMatch(model, /headline.*title|gameDay.*game_day|isNew.*is_new/);
  assert.match(panel, /List<NewsStory> news/);
  assert.doesNotMatch(panel, /item\['headline'\]|item\['game_day'\]|item\['is_new'\]/);
});
