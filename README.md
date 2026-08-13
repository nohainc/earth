# EARTH

EARTH is a web-first prototype of a persistent economic and civic simulation based on the accompanying game specification and technical architecture documents.

## Run

For the visual prototype, open `index.html` in this folder. It launches the current Prototype 3 experience from the project root.

For the authoritative API prototype:

```bash
cd earth
npm install
npm start
```

The server listens on `http://localhost:8787` and exposes `GET /api/world`, market order and settlement commands, business policy, research funding, governance ballots, and day advancement. Set `DATABASE_URL` to enable PostgreSQL persistence; without it, the server deliberately runs in an in-memory development mode. `GET /api/storage` reports which mode is active.

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

The Flutter client scaffold is in `flutter_client/`. It targets Web, iOS, and macOS and reads canonical world state from the prototype API.

## Repository map

- `server.js` — authoritative prototype API and event stream
- `database.js` — optional PostgreSQL write-through adapter
- `db/migrations/001_initial.sql` — relational world schema
- `db/seed.sql` — initial OUC / City / Corporation / Human world
- `prototype3.html` — selected futuristic web client
- `flutter_client/` — shared Flutter client foundation
- `test/server.smoke.test.js` — end-to-end command and invariant checks

## Verification

```bash
npm run check
npm test
```

## Current playable systems

- world pulse and health signals
- Credit, Standing, Legacy, and market-batch status
- Central Market pressure signals and order intent
- business operating state
- civic proposal review and ballot recording
- Technology Registry research funding
- simulated day advancement
- authoritative prototype API with ledger entries and auditable command outcomes
- aurora/night and daylight themes

## Architectural direction

The prototype follows the specification's decision-first, server-authoritative model at the UX boundary: the player submits intent, while settlement, governance outcomes, ledger changes, and simulation results remain canonical system outcomes. The next production step is replacing the local interaction layer with a TypeScript modular monolith, PostgreSQL ledger/history, and coordinated market/governance state.
