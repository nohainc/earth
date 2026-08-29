import type { Env } from './index.ts';
import { withRepository } from './repository.ts';
import { parseJsonBody, resolveIdempotencyKey } from './request-validation.ts';
import {
  listMarketOrdersPostgres,
  submitMarketOrderPostgres,
  cancelMarketOrderPostgres,
  settleMarketPostgres,
  listMarketPriceHistoryPostgres,
} from './market-postgres.ts';
import {
  listCommodityDerivativesAndOHLC,
  createFuturesListing,
  matchFuturesContract,
  cancelFuturesListing,
} from './derivatives-postgres.ts';

export async function handleMarketRoutes(
  request: Request,
  env: Env,
  url: URL,
  viewer: { id: string },
): Promise<Response | null> {
  if (url.pathname === '/api/market/book' && request.method === 'GET') {
    const result = await withRepository(env, async (repository) => {
      const [rows, trades, rule] = await Promise.all([
        repository.query("SELECT product, status, SUM(quantity - filled_quantity) AS open_quantity, MIN(limit_price) AS best_price, COUNT(*) AS order_count FROM market_orders WHERE status IN ('open','partial') GROUP BY product, status ORDER BY product"),
        repository.query('SELECT product, SUM(quantity) AS traded_quantity, MAX(clearing_price) AS last_price, MAX(created_at) AS last_trade_at FROM market_trades GROUP BY product ORDER BY product'),
        repository.query("SELECT rate FROM tax_rules WHERE scope = 'global' AND category = 'market' AND active = true LIMIT 1"),
      ]);
      const feeRate = Number(rule.rows[0]?.rate ?? 0);
      return { book: rows.rows, trades: trades.rows, feeRate };
    });
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/market/orders' && request.method === 'GET') {
    const result = await withRepository(env, (repository) => listMarketOrdersPostgres(repository, url.searchParams.get('product')));
    if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
    return Response.json({ ...result, persistence: 'planetscale-postgres' });
  }

  if (url.pathname === '/api/market/orders' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ product?: string; quantity?: number; limitPrice?: number; side?: string; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const product = body.product;
    const side = body.side === 'sell' ? 'sell' : 'buy';
    const quantity = Number(body.quantity);
    const limitPrice = Number(body.limitPrice);
    if (!['food', 'material', 'components', 'energy', 'compute'].includes(product ?? '') || !Number.isInteger(quantity) || quantity <= 0 || !Number.isFinite(limitPrice) || limitPrice <= 0) {
      return Response.json({ ok: false, error: 'Invalid market order' }, { status: 400 });
    }
    const correlationId = resolveIdempotencyKey(request, body.correlationId);
    if (!correlationId) return Response.json({ ok: false, error: 'Idempotency-Key conflicts with correlationId or is too long' }, { status: 400 });
    try {
      const result = await withRepository(env, (repository) =>
        submitMarketOrderPostgres(repository, { humanId: viewer.id, product: product!, side, quantity, limitPrice, correlationId }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Market order failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient|reservation/i.test(message) ? 409 : 400 });
    }
  }

  const cancelOrderMatch = url.pathname.match(/^\/api\/market\/orders\/([^/]+)$/);
  if (cancelOrderMatch && request.method === 'DELETE') {
    try {
      const result = await withRepository(env, (repository) =>
        cancelMarketOrderPostgres(repository, { orderId: cancelOrderMatch[1], humanId: viewer.id }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market order cancellation failed' }, { status: 404 });
    }
  }

  if (url.pathname === '/api/market/settle' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ product?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const body = parsed.value;
    const product = body.product;
    if (!['food', 'material', 'components', 'energy', 'compute'].includes(product ?? '')) {
      return Response.json({ ok: false, error: 'Unknown product' }, { status: 400 });
    }
    try {
      const result = await withRepository(env, (repository) => settleMarketPostgres(repository, product!));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market settlement failed' }, { status: 409 });
    }
  }

  if (url.pathname === '/api/market/derivatives' && request.method === 'GET') {
    const commodity = url.searchParams.get('commodity')?.trim() ?? 'energy';
    try {
      const result = await withRepository(env, (repository) =>
        listCommodityDerivativesAndOHLC(repository, commodity, viewer.id),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to fetch derivatives';
      return Response.json({ ok: false, error: message }, { status: 400 });
    }
  }

  if (url.pathname === '/api/market/futures/create' && request.method === 'POST') {
    const parsed = await parseJsonBody<{ commodity?: string; size?: number; strikePrice?: number; expiryGameDay?: number; correlationId?: string }>(request);
    if (!parsed.ok) return parsed.response;
    const commodity = parsed.value.commodity?.toLowerCase().trim() ?? 'energy';
    const size = Number(parsed.value.size);
    const strikePrice = Number(parsed.value.strikePrice);
    const expiryGameDay = Number(parsed.value.expiryGameDay);
    const correlationId = resolveIdempotencyKey(request, parsed.value.correlationId);

    try {
      const result = await withRepository(env, (repository) =>
        createFuturesListing(repository, {
          sellerId: viewer.id,
          commodity,
          size,
          strikePrice,
          expiryGameDay,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Futures creation failed';
      return Response.json({ ok: false, error: message }, { status: /insufficient/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname.startsWith('/api/market/futures/') && url.pathname.endsWith('/buy') && request.method === 'POST') {
    const segments = url.pathname.split('/');
    const contractId = segments[4];
    if (!contractId) return Response.json({ ok: false, error: 'Contract ID is required' }, { status: 400 });
    const correlationId = resolveIdempotencyKey(request);

    try {
      const result = await withRepository(env, (repository) =>
        matchFuturesContract(repository, {
          buyerId: viewer.id,
          contractId,
          correlationId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Futures matching failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : /insufficient/i.test(message) ? 409 : 400 });
    }
  }

  if (url.pathname.startsWith('/api/market/futures/') && url.pathname.endsWith('/cancel') && request.method === 'POST') {
    const segments = url.pathname.split('/');
    const contractId = segments[4];
    if (!contractId) return Response.json({ ok: false, error: 'Contract ID is required' }, { status: 400 });

    try {
      const result = await withRepository(env, (repository) =>
        cancelFuturesListing(repository, {
          sellerId: viewer.id,
          contractId,
        }),
      );
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Futures cancellation failed';
      return Response.json({ ok: false, error: message }, { status: /not found/i.test(message) ? 404 : 400 });
    }
  }

  if (url.pathname === '/api/market/history' && request.method === 'GET') {
    const product = url.searchParams.get('product')?.trim() ?? 'material';
    const days = Number(url.searchParams.get('days') ?? 30);
    try {
      const result = await withRepository(env, (repository) => listMarketPriceHistoryPostgres(repository, product, days));
      if (!result) return Response.json({ ok: false, error: 'PostgreSQL persistence is unavailable' }, { status: 503 });
      return Response.json({ ...result, persistence: 'planetscale-postgres' });
    } catch (error) {
      return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Market price history fetch failed' }, { status: 500 });
    }
  }

  return null;
}
