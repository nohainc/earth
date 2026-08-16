# EARTH

EARTH is a web-first prototype of a persistent economic and civic simulation based on the accompanying game specification and technical architecture documents.

## Run

For the visual prototype, open `index.html` in this folder. It launches the current Prototype 3 experience from the project root.

For the local reference API simulator:

```bash
cd earth
npm install
npm start
```

The server listens on `http://localhost:8787` and exposes the compatibility
API. It is non-production and never a fallback for the Cloudflare Worker. Set
`DATABASE_URL` when hydrating the simulator from PostgreSQL; production
gameplay uses the PostgreSQL-backed Worker API.

To provision the recommended local PostgreSQL authority:

```bash
docker compose up -d postgres
```

The Compose setup mounts the migration and seed files directly into PostgreSQL's initialization directory so a fresh volume is created in the correct order.

On macOS without Docker, use the Homebrew PostgreSQL service:

```bash
brew install postgresql@16
brew services start postgresql@16
createdb earth
psql -d earth -f db/migrations/001_initial.sql
psql -d earth -f db/seed.sql
DATABASE_URL=postgres://$USER@localhost:5432/earth npm start
```

The Flutter client in `flutter_client/` is the production web application. It reads canonical state from the Cloudflare Worker API backed by PlanetScale PostgreSQL through Hyperdrive. The public landing page is served at `/landing`; the authenticated application is served at `/app`.

To run Flutter against the deployed Worker and PostgreSQL-backed API:

```bash
cd flutter_client
flutter pub get
flutter run -d chrome --dart-define=EARTH_API_URL=https://earthuc.com
```

For a release build served by Workers Static Assets:

```bash
flutter build web --release --base-href /
cd ..
npx wrangler deploy --domains earthuc.com
```

## API contract

The versioned REST/JSON error and authority contract is documented in
[`docs/API_CONTRACT.md`](docs/API_CONTRACT.md). The current response version is
`2026-08`.

## Repository map

- `server.js` — non-production reference API and event stream
- `database.js` — optional PostgreSQL write-through adapter
- `db/migrations/001_initial.sql` — relational world schema
- `db/seed.sql` — initial United Corporations / City / Corporation / Human world
- `prototype3.html` — selected futuristic web client
- `flutter_client/` — shared Flutter client foundation
- `test/server.smoke.test.js` — end-to-end command and invariant checks

## Verification

```bash
npm run check
npm test
npm run simulate:scenarios
```

## Current playable systems

- world pulse and health signals
- Credit, Standing, Legacy, and market-batch status
- Central Market pressure signals and order intent
- business operating state
- civic proposal review and ballot recording
- Technology Registry research funding
- parameterized R&D focus with production and wear trade-offs
- machine lifecycle: acquisition, maintenance, upgrade, resale, recycling
- bounded Basic/Business AI assistants and explainable recommendations
- macro liquidity corridor reporting and essential-service lifecycle effects
- simulated day advancement
- authoritative prototype API with ledger entries and auditable command outcomes
- aurora/night futuristic visual system with a consistent command-center UI

## PostgreSQL and Flutter verification

The authoritative production schema is tracked in `db/migrations/` and runs in
PlanetScale PostgreSQL through the Hyperdrive binding. Verify the database
before deploying:

```bash
DATABASE_URL="$DATABASE_URL" npm run db:migrate:postgres
DATABASE_URL="$DATABASE_URL" npm run db:verify:manifest
npm run cf:smoke
```

The production smoke suite also verifies that `/app` serves the compiled Flutter shell, protected API and event endpoints reject unauthenticated access, and the remote PostgreSQL feature schema is present.

The Flutter client is the primary production/test client; local Node/PostgreSQL code remains a reference simulator and compatibility test harness, not the deployed game authority.

## Architectural direction

The implementation follows the specification's decision-first, server-authoritative model: the player submits intent, while settlement, governance outcomes, ledger changes, and simulation results remain canonical PostgreSQL/Worker outcomes. Durable Objects coordinate market commands and live events; PostgreSQL remains the authoritative economic state.
