import type { Env } from './index.ts';
import { withRepository } from './postgres.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  createContractPostgres,
  acceptContractPostgres,
  rejectContractPostgres,
  cancelContractPostgres,
} from './contracts-postgres.ts';
import {
  listSupplyContracts,
  proposeSupplyContract,
  acceptSupplyContract,
  cancelSupplyContract,
} from './supply-contracts-postgres.ts';
import { openDisputePostgres, resolveContractDisputePostgres } from './arbitration-postgres.ts';

export async function handleContractRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/contracts' && request.method === 'GET') {
    const result = await withRepository(env, (repository) =>
      repository.query(
        "SELECT negotiated_contracts.*, contract_disputes.id AS dispute_id, contract_disputes.status AS dispute_status, contract_disputes.reason AS dispute_reason FROM negotiated_contracts LEFT JOIN contract_disputes ON contract_disputes.contract_id = negotiated_contracts.id AND contract_disputes.status = 'open' WHERE negotiated_contracts.proposer_id = $1 OR negotiated_contracts.counterparty_id = $1 ORDER BY negotiated_contracts.created_at DESC LIMIT 50",
        [viewer.id],
      ),
    );
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ contracts: result.rows, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/contracts' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      kind?: string;
      counterpartyId?: string;
      title?: string;
      terms?: Record<string, unknown>;
      amount?: number;
      durationDays?: number;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const kind = body.kind?.trim() ?? '';
    const counterpartyId = body.counterpartyId?.trim() ?? '';
    const title = body.title?.trim() ?? '';
    const amount = Math.round(Number(body.amount ?? 0) * 100) / 100;
    const durationDays = Number(body.durationDays ?? 30);
    if (!['employment', 'intellectual_service', 'capacity', 'strategic'].includes(kind)) {
      return Response.json({ ok: false, error: 'Unsupported contract kind' }, { status: 400 });
    }
    const counterparty = await withRepository(env, (repository) =>
      repository.query("SELECT id FROM humans WHERE id = $1 AND life_status = 'active'", [counterpartyId]),
    );
    if (!counterpartyId || counterpartyId === viewer.id || !counterparty?.rows[0]) {
      return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
    }
    if (title.length < 3 || title.length > 140 || !Number.isFinite(amount) || amount < 0 || amount > 100000 || !Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) {
      return Response.json({ ok: false, error: 'Contract terms are outside engine bounds' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        createContractPostgres(repository, {
          proposerId: viewer.id,
          kind,
          counterpartyId,
          title,
          terms: body.terms ?? {},
          amount,
          durationDays,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyProcessed ? 200 : 201 });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Contract creation failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/contracts/supply' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listSupplyContracts(repository, viewer.id));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/contracts/supply/propose' && request.method === 'POST') {
    const parsed = await parseJsonBody<{
      counterpartyId?: string;
      proposerRole?: 'buyer' | 'seller';
      resourceType?: 'food' | 'energy' | 'material' | 'compute';
      dailyQuantity?: number;
      unitPrice?: number;
      totalDays?: number;
      penaltyPerDefault?: number;
      title?: string;
      correlationId?: string;
    }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const counterpartyId = body.counterpartyId?.trim() ?? '';
    const proposerRole = body.proposerRole === 'seller' ? 'seller' : 'buyer';
    const resourceType = body.resourceType ?? 'energy';
    const dailyQuantity = Number(body.dailyQuantity ?? 0);
    const unitPrice = Number(body.unitPrice ?? 0);
    const totalDays = Number(body.totalDays ?? 30);
    const penaltyPerDefault = Number(body.penaltyPerDefault ?? 0);
    const title = body.title?.trim();

    if (!counterpartyId || counterpartyId === viewer.id) {
      return Response.json({ ok: false, error: 'An active counterparty Human is required' }, { status: 400 });
    }
    if (!['food', 'energy', 'material', 'compute'].includes(resourceType)) {
      return Response.json({ ok: false, error: 'Invalid commodity resource type' }, { status: 400 });
    }
    if (dailyQuantity <= 0 || unitPrice <= 0 || totalDays < 1 || totalDays > 365) {
      return Response.json({ ok: false, error: 'Quantity, price, and duration are outside engine bounds' }, { status: 400 });
    }

    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key is required' }, { status: 400 });

    try {
      const result = await withRepository(env, (repository) =>
        proposeSupplyContract(repository, {
          proposerId: viewer.id,
          counterpartyId,
          proposerRole,
          resourceType,
          dailyQuantity,
          unitPrice,
          totalDays,
          penaltyPerDefault,
          title,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Supply contract proposal failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient|balance/i.test(message) ? 409 : 400 });
    }
  }

  const supplyContractMatch = url.pathname.match(/^\/api\/contracts\/supply\/([^/]+)\/(accept|cancel)$/);
  if (supplyContractMatch && request.method === 'POST') {
    const contractId = supplyContractMatch[1];
    const action = supplyContractMatch[2];
    const correlationId = resolveIdempotencyKey(request);

    try {
      const result = await withRepository(env, (repository) => {
        if (action === 'accept') {
          return acceptSupplyContract(repository, { humanId: viewer.id, contractId, correlationId });
        }
        return cancelSupplyContract(repository, { humanId: viewer.id, contractId });
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Supply contract action failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /only .* may|unauthorized/i.test(message) ? 403 : 409 });
    }
  }

  const contractActionMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(accept|reject|cancel)$/);
  if (contractActionMatch && request.method === 'POST') {
    try {
      const result = await withRepository(env, (repository) => {
        if (contractActionMatch[2] === 'cancel') return cancelContractPostgres(repository, contractActionMatch[1], viewer.id);
        if (contractActionMatch[2] === 'reject') return rejectContractPostgres(repository, contractActionMatch[1], viewer.id);
        return acceptContractPostgres(repository, contractActionMatch[1], viewer.id);
      });
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Contract action failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /only .* may/i.test(message) ? 403 : 409 });
    }
  }

  const contractDisputeMatch = url.pathname.match(/^\/api\/contracts\/([^/]+)\/(dispute|resolve)$/);
  if (contractDisputeMatch && request.method === 'POST') {
    try {
      if (contractDisputeMatch[2] === 'dispute') {
        const parsed = await parseJsonBody<{ reason?: string }>(request);
        if (!parsed.ok) return parsed.response;
        const body = parsed.value;
        const reason = body.reason?.trim() ?? '';
        if (reason.length < 10 || reason.length > 1000) return Response.json({ ok: false, error: 'A dispute reason must be 10–1000 characters' }, { status: 400 });
        const result = await withRepository(env, (repository) => openDisputePostgres(repository, { contractId: contractDisputeMatch[1], claimantId: viewer.id, reason }));
        if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
        return Response.json({ ...result, persistence: 'planetscale-postgres' }, { status: result.alreadyOpen ? 200 : 201 });
      }
      const parsed = await parseJsonBody<{ outcome?: string; resolution?: string }>(request);
      if (!parsed.ok) return parsed.response;
      const body = parsed.value;
      if (!['uphold', 'void'].includes(body.outcome ?? '') || (body.resolution?.trim().length ?? 0) < 10) return Response.json({ ok: false, error: 'A bounded arbitration outcome and resolution are required' }, { status: 400 });
      const result = await withRepository(env, (repository) =>
        resolveContractDisputePostgres(repository, { contractId: contractDisputeMatch[1], resolverId: viewer.id, outcome: body.outcome as 'uphold' | 'void', resolution: body.resolution!.trim().slice(0, 1000) }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Contract dispute operation failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /authority|required|only/i.test(message) ? 403 : 409 });
    }
  }

  return null;
}
