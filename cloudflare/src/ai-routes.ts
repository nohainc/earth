import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody } from './request-validation.ts';
import { currentHuman, sensitiveActionAllowed } from './auth-session.ts';
import { listAssistants, recordRecommendationFeedback, updateAssistantPolicy, upgradeAssistant } from './ai-postgres.ts';

/**
 * Handles all routes under /api/ai/*
 *
 * AI assistant tiers:
 *   basic    — rule-based alert recommendations and maintenance policy
 *   business — same as basic; future: bounded automation and priority signals
 *
 * The AI feature is currently a rule-based advisory system. It does NOT call an
 * external LLM or ML inference endpoint. The assistant reads the player's world
 * snapshot and evaluates deterministic heuristics (see decision-queue.ts and
 * objectives.ts) to surface prioritised alerts. "Business AI" tier unlocks the
 * maintenance policy mode and is a paid in-game upgrade (2,400 Credits).
 */
export async function handleAiRoutes(
  request: Request,
  env: Env,
  url: URL,
): Promise<Response | null> {
  // GET /api/ai — list assistants for the authenticated player
  if (url.pathname === '/api/ai' && request.method === 'GET') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const result = await withRepository(env, (repository) => listAssistants(repository, viewer.id));
    return Response.json({
      ...result,
      // Constraints surfaced to the Flutter client so the UI can show or hide policy options
      constraints: {
        governance: false,       // AI may not autonomously cast governance votes
        authority: false,        // AI may not perform sensitive auth actions
        allowedPolicies: ['recommend', 'maintenance'],
      },
      // Metadata for the UI advisory display
      advisorMeta: {
        engineType: 'rule-based',    // Not an LLM — deterministic heuristics only
        dataSource: 'world_snapshot', // Reads from PostgreSQL world snapshot
        canAutoExecute: false,        // All actions require explicit player approval
      },
      persistence: 'planetscale-postgres',
    });
  }

  // POST /api/ai/policy — update the assistant policy (recommend | maintenance)
  if (url.pathname === '/api/ai/policy' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ assistantId?: string; policy?: string; enabled?: boolean }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!body.assistantId || !['recommend', 'maintenance'].includes(body.policy ?? '')) {
      return Response.json({ ok: false, error: 'Basic AI supports only recommend or maintenance policies' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        updateAssistantPolicy(repository, {
          ownerId: viewer.id,
          assistantId: body.assistantId!,
          policy: body.policy ?? 'recommend',
          enabled: body.enabled !== false,
        }),
      );
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'AI assistant not found' }, { status: 404 });
    }
  }

  // POST /api/ai/upgrade — upgrade assistant tier from basic to business (costs 2,400 Credits)
  if (url.pathname === '/api/ai/upgrade' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ assistantId?: string; otp?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!(await sensitiveActionAllowed(env, viewer.id, body.otp))) {
      return Response.json({ ok: false, error: 'Authenticator code required for AI upgrade' }, { status: 401 });
    }
    try {
      const result = await withRepository(env, (repository) =>
        upgradeAssistant(repository, { ownerId: viewer.id, assistantId: body.assistantId ?? '' }),
      );
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'AI upgrade failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 404 });
    }
  }

  if (url.pathname === '/api/ai/feedback' && request.method === 'POST') {
    const viewer = await currentHuman(request, env);
    if (!viewer) return Response.json({ ok: false, error: 'Authentication required' }, { status: 401 });
    const parsed = await parseJsonBody<{ recommendationType?: string; recommendationId?: string; action?: string; contextSnapshot?: unknown }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    if (!['decision_queue', 'objective', 'briefing'].includes(body.recommendationType ?? '') || !body.recommendationId || !['approved', 'dismissed', 'deferred', 'viewed'].includes(body.action ?? '')) {
      return Response.json({ ok: false, error: 'Invalid recommendation feedback' }, { status: 400 });
    }
    const result = await withRepository(env, (repository) => recordRecommendationFeedback(repository, {
      humanId: viewer.id, recommendationType: body.recommendationType as 'decision_queue' | 'objective' | 'briefing', recommendationId: body.recommendationId,
      action: body.action as 'approved' | 'dismissed' | 'deferred' | 'viewed', contextSnapshot: body.contextSnapshot,
    }));
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  return null; // Not an AI route — let index.ts continue
}
