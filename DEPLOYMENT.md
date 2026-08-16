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

## Manual GitHub deployments

Deployments are intentionally manual. GitHub pushes and pull requests run the
test workflow only; they do not publish production changes.

From the repository's GitHub Actions tab, run one of these workflows with
`workflow_dispatch`:

- **Deploy EARTH web app** (`deploy-web.yml`) — builds and deploys only the
  Flutter app Worker for `/app`.
- **Deploy EARTH API** — validates and deploys only the API Worker for `/api/*`,
  `/edge/*`, `/health`, and `/ready`.
- **Deploy EARTH landing and static files** — copies and deploys only the
  landing/static Worker for the public catch-all route.

Both workflows support the configured `staging` and `production` Wrangler
environments. Configure these GitHub Actions secrets before running them:

- `CLOUDFLARE_API_TOKEN` — a token permitted to deploy Workers and Static Assets
- `CLOUDFLARE_ACCOUNT_ID` — the Cloudflare account containing the Worker

The three Workers use Cloudflare route patterns so the same `earthuc.com` domain
is split by responsibility. The API and app workflows do not rebuild or upload
landing/static files, and the landing/static workflow does not rebuild Flutter.
The Cloudflare zone must have the route patterns from `wrangler.api.jsonc`,
`wrangler.app.jsonc`, and `wrangler.static.jsonc` available to the deployment
account before the first production run.

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

Local databases also need the canonical starter world after migrations:

```bash
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:seed:postgres
```

The release is blocked if PostgreSQL connectivity, schema/data readiness, or
the stable API error contract fails.

The Flutter web build is tested against the deployed API with
`--dart-define=EARTH_API_URL=https://earthuc.com`; production uses the same
Worker and PlanetScale PostgreSQL authority. Earth has no active D1 database
or D1 runtime path.
