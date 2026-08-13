# EARTH deployment plan

The prototype uses a modular-monolith boundary first, matching the technical architecture document.

## Local

```bash
npm install
docker compose up -d postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm start
```

## Cloudflare target

- Cloudflare Workers: edge API and static routing
- Hyperdrive: connection acceleration to the managed PostgreSQL database
- Durable Objects: serialized market batches, governance coordinators, and live sessions
- Queues: retryable notifications, statistics, aging, and settlement side effects
- R2: reports, logos, exports, and future media

The current `server.js` is the local authoritative reference implementation. The next deployment adapter should preserve its command/query contract while moving HTTP routing to a Worker and database access behind Hyperdrive.

## Secrets

Never commit `DATABASE_URL` or Cloudflare credentials. Use `.env` locally and Wrangler secrets in deployed environments.
