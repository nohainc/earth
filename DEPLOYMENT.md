# EARTH deployment plan

The prototype uses a modular-monolith boundary first, matching the technical architecture document.

## Local

```bash
npm install
docker compose up -d postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm start
```

## Public preview

- Landing page: https://earthuc.com/landing
- Authenticated Flutter application: https://earthuc.com/app
- Worker API: https://earth-world.vitalii-e07.workers.dev

The Worker serves the compiled Flutter web client from `flutter_client/build/web` at `/app`. The repository-root `index.html` and `landing.css` are the standalone marketing landing-page source; `/landing` is the public entry point and `/` redirects there.

## Cloudflare target

- Cloudflare Workers Static Assets: unified Flutter client, edge API, and static routing
- Hyperdrive: connection acceleration to the managed PostgreSQL database
- Durable Objects: serialized market batches, governance coordinators, and live sessions
- Queues: future retryable notifications, statistics, aging, and settlement side effects
- R2: reports, logos, exports, and future media

The current `server.js` remains the local PostgreSQL reference implementation. The deployed game client uses the PostgreSQL-backed Worker API above; the Flutter client is the primary web UI.

## Secrets

Never commit `DATABASE_URL` or Cloudflare credentials. Use `.env` locally and Wrangler secrets in deployed environments.

## Production PostgreSQL verification

```bash
DATABASE_URL="$DATABASE_URL" npm run db:verify:manifest
DATABASE_URL="$DATABASE_URL" D1_EXPORT=backups/earth-d1-cutover-backup.sql npm run db:verify:d1-postgres
npm run cf:smoke
```

The Flutter web build is tested against the deployed API with `--dart-define=EARTH_API_URL=https://earthuc.com`; production uses the same Worker and PlanetScale PostgreSQL authority.
