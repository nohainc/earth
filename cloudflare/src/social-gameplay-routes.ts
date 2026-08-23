import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody } from './request-validation.ts';
import {
  createSocialInitiative,
  listSocialInitiatives,
  listSocialDirectory,
  listSocialTimeline,
  listSocialRelationships,
  respondToSocialInitiative,
  contributeToSocialInitiative,
  type SocialKind,
} from './social-gameplay-postgres.ts';

export async function handleSocialRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/social/initiatives' && request.method === 'GET') {
    const initiatives = await withRepository(env, (repo) => listSocialInitiatives(repo, viewer.id));
    return Response.json({ ok: true, initiatives: initiatives ?? [] });
  }

  if (url.pathname === '/api/social/directory' && request.method === 'GET') {
    const directory = await withRepository(env, (repo) => listSocialDirectory(repo, viewer.id, url.searchParams.get('q') ?? ''));
    return Response.json({ ok: true, ...directory });
  }

  if (url.pathname === '/api/social/relationships' && request.method === 'GET') {
    const relationships = await withRepository(env, (repo) => listSocialRelationships(repo, viewer.id));
    return Response.json({ ok: true, relationships: relationships ?? [] });
  }

  if (url.pathname === '/api/social/timeline' && request.method === 'GET') {
    const timeline = await withRepository(env, (repo) => listSocialTimeline(repo, viewer.id, Number(url.searchParams.get('limit') ?? 50)));
    return Response.json({ ok: true, timeline: timeline ?? [] });
  }

  if (url.pathname === '/api/social/initiatives' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ targetId?: string; kind?: SocialKind; title?: string; body?: string; terms?: Record<string, unknown>; gameDay?: number }>(request);
    if (!parsed.ok) return parsed.response;
    const value = parsed.value;
    if (!value.kind || !value.title?.trim() || !value.body?.trim()) {
      return Response.json({ ok: false, error: 'kind, title, and body are required' }, { status: 400 });
    }
    const initiative = await withRepository(env, (repo) =>
      createSocialInitiative(repo, { creatorId: viewer.id, targetId: value.targetId, kind: value.kind!, title: value.title!.trim(), body: value.body!.trim(), terms: value.terms, gameDay: value.gameDay }),
    );
    return Response.json({ ok: true, initiative });
  }

  const socialResponse = url.pathname.match(/^\/api\/social\/initiatives\/([^/]+)\/(accept|decline|contribute)$/);
  if (socialResponse && request.method === 'POST') {
    const parsed = await parseJsonBody<{ contribution?: number }>(request);
    if (!parsed.ok) return parsed.response;
    const result = await withRepository(env, (repo) =>
      socialResponse[2] === 'contribute'
        ? contributeToSocialInitiative(repo, viewer.id, socialResponse[1], Number(parsed.value.contribution ?? 1))
        : respondToSocialInitiative(repo, viewer.id, socialResponse[1], socialResponse[2] === 'accept'),
    );
    return Response.json({ ok: true, initiative: result });
  }

  return null;
}
