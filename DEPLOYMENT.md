# EARTH deployment plan

The prototype uses a modular-monolith boundary first, matching the technical architecture document.

## Local

```bash
npm install
docker compose up -d postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm start
```

## Public preview

- Primary virtual world: https://earthuc.com
- Pages rollback client: https://earth-client.pages.dev
- Immutable deployment: https://3b432e42.earth-client.pages.dev
- Worker API: https://earth-world.vitalii-e07.workers.dev

## Cloudflare target

- Cloudflare Workers Static Assets: unified Flutter client, edge API, and static routing
- Hyperdrive: connection acceleration to the managed PostgreSQL database
- Durable Objects: serialized market batches, governance coordinators, and live sessions
- Queues: retryable notifications, statistics, aging, and settlement side effects
- R2: reports, logos, exports, and future media

The current `server.js` remains the local PostgreSQL reference implementation. The deployed game client uses the D1-backed Worker API above; the Flutter client is the primary web UI.

## Secrets

Never commit `DATABASE_URL` or Cloudflare credentials. Use `.env` locally and Wrangler secrets in deployed environments.
