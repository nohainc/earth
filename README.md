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
psql -d earth -f db/initial.sql
psql -d earth -f db/seed.sql
DATABASE_URL=postgres://$USER@localhost:5432/earth npm start
```

For an existing local database, apply the migrations and load the canonical
starter world explicitly:

```bash
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:migrate:postgres
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:seed:postgres
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:verify:manifest
```

For manual local PostgreSQL testing, use the same database for migrations and
the local Worker API. The migration helper defaults to the Docker database:

```bash
./scripts/migrate-local-db.sh --seed
DATABASE_READ_ONLY=false DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth npm run start:wrangler
```

The Flutter client should then use `http://localhost:8788`. The legacy
`server.js` reference simulator is intended for automated tests and is not the
manual PostgreSQL-backed application path.

To exercise the same scheduled settlement path as production, start the local
app through `./scripts/run-local-ui-test.sh` and then run:

```bash
./scripts/run-local-game-tick.sh
```

The local Worker uses Wrangler's scheduled-event test endpoint. It advances one
game hour, rebuilds any dirty settlement profiles, and applies prepared normal
resource deltas through PostgreSQL.


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

## API contract and data formats

The versioned REST error and authority contract is documented in
[`docs/API_CONTRACT.md`](docs/API_CONTRACT.md). The current response version is
`2026-08`. Internal serialized state strings, world event details, negotiated contract terms, governance rule values, and municipal charters are serialized using **Nano Markup** (`nanomarkup` by `nohainc`).

Product and architecture guardrails for future AI-assisted development are in
[`docs/AI_DEVELOPMENT_GUIDE.md`](docs/AI_DEVELOPMENT_GUIDE.md).
The implementation checklist for the management-first redesign is in
[`docs/GAMEPLAY_REDESIGN_AUDIT.md`](docs/GAMEPLAY_REDESIGN_AUDIT.md).

## Repository map

- `cloudflare/` — authoritative production Cloudflare Worker API & settlement engine
- `flutter_client/` — multiplatform production client (Web, macOS, iOS, Android, Linux, Windows)
- `db/migrations/` — relational PostgreSQL schema and versioned migrations (001–054)
- `db/seed.sql` — initial United Corporations / City / Corporation / Human world
- `server.js` — non-production local reference API
- `test/` — comprehensive automated test suites (Node.js test runner)

## Verification

```bash
npm run check
npm test
npm run qa
```

## Current playable systems

- **Building-Centric Urban Economy**: Self-contained private estates, civic infrastructure, and public investment megaprojects with multi-day construction pipelines, daily operating credit ledgers, auto-repair, and 70/30 weighted citizen dividends.
- **Corporate Technology & Patent Licensing**: Foundational open technology + corporate patent IP licensing (private, city-wide civic, permanent).
- **Industrial Machine Operations**: Independent tradable manufacturing assets for specialized commodity fabrication, research facilities, and logistics.
- **Civic Governance & Quadratic Ballots**: Sovereign city charters, taxation policies, municipal megaproject procurement, and diplomatic dispatches.
- **Central Commodity Market**: Live liquidity corridors, order books, OHLC data tracking, and futures delivery contracts.
- **Persistent World Simulation**: Atomic financial ledger transfers, scheduled maintenance, and deterministic daily settlements.

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

The Flutter client is the primary production/test client. Local PostgreSQL is the
same authoritative persistence model used for manual production-like testing;
the local Node server and `simulate:scenarios` command are compatibility and
balance-verification tools only, not a separate player-facing game mode.

## Architectural direction

The implementation follows the specification's decision-first, server-authoritative model: the player submits intent, while settlement, governance outcomes, ledger changes, and persistent world-engine results remain canonical PostgreSQL/Worker outcomes. Durable Objects coordinate market commands and live events; PostgreSQL remains the authoritative economic state.
