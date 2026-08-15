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
- Queues: retryable notifications, statistics, aging, and settlement side effects
- R2: reports, logos, exports, and future media

The current `server.js` remains the local PostgreSQL reference implementation. The deployed game client uses the D1-backed Worker API above; the Flutter client is the primary web UI.

## Secrets

Never commit `DATABASE_URL` or Cloudflare credentials. Use `.env` locally and Wrangler secrets in deployed environments.

## Remote D1 verification

```bash
npx wrangler d1 migrations list earth-world --remote
npx wrangler d1 execute earth-world --remote --command "SELECT 1 AS ok;"
npm run cf:smoke
```

The Flutter web build is tested against the deployed API with `--dart-define=EARTH_API_URL=https://earthuc.com`; production uses the same Worker and remote D1 path.
