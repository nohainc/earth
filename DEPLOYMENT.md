# EARTH deployment plan

The deployed system uses a modular-monolith boundary first, matching the
technical architecture document. The local `server.js` process is a
non-production reference simulator only.

## Local

```bash
npm install
docker compose up -d postgres
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm start
```

## Public preview

- Landing page: https://earthuc.com/landing
- Authenticated Flutter application: https://earthuc.com/app
- Worker API: https://earth-world-production.vitalii-e07.workers.dev

The Worker serves the compiled Flutter web client from `flutter_client/build/web` at `/app`. The repository-root `index.html` and `landing.css` are the standalone marketing landing-page source; `/landing` is the public entry point and `/` redirects there.

The `earthuc.com` custom domain is attached to the `earth-world-production`
Worker. If the direct Worker URL and custom domain ever show different UI
versions, inspect the custom-domain attachment before debugging Flutter code.

## Cloudflare target

- Cloudflare Workers Static Assets: unified Flutter client, edge API, and static routing
- Hyperdrive: connection acceleration to the managed PostgreSQL database
- Durable Objects: serialized market batches, governance coordinators, and live sessions
- Queues: future retryable notifications, statistics, aging, and settlement side effects
- R2: reports, logos, exports, and future media

The current `server.js` is a local compatibility/reference simulator only. It
is not deployed and is not a fallback authority. The deployed game client uses
the PostgreSQL-backed Worker API above; the Flutter client is the primary web UI.

## Secrets

Never commit `DATABASE_URL` or Cloudflare credentials. Use `.env` locally and Wrangler secrets in deployed environments.

## Production PostgreSQL verification

```bash
DATABASE_URL="$DATABASE_URL" npm run db:verify:manifest
npm run cf:smoke
```

The release is blocked if PostgreSQL connectivity, schema/data readiness, or
the stable API error contract fails.

The Flutter web build is tested against the deployed API with
`--dart-define=EARTH_API_URL=https://earthuc.com`; production uses the same
Worker and PlanetScale PostgreSQL authority. Earth has no active D1 database
or D1 runtime path.
