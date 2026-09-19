# EARTH

EARTH is a persistent web-first economic, civic, and generational simulation.

Gameplay V5 is the active gameplay model. PostgreSQL is the canonical state
authority; the Cloudflare Worker validates and executes commands; Flutter is the
production client.

## Canonical gameplay model

- **EARTH** — global authority and constitutional framework.
- **Corporation** — local political/economic institution.
- **House** — persistent player identity and private economic principal.
- **Human** — mortal representative of a House.
- **Community** — voluntary social association.
- **Territory** — physical/geographic capacity context, not a government.
- **City** — obsolete domain concept; do not add City gameplay or APIs.

See `docs/DOCUMENT_STATUS.md` and `docs/v5/README.md` before gameplay changes.

## Repository map

- `cloudflare/` — production Cloudflare Worker API and settlement engine
- `flutter_client/` — production Flutter client
- `db/migrations/` — append-only forward PostgreSQL migration history
- `db/schema.sql` — current canonical schema artifact
- `db/schema-manifest.json` — schema contract/manifest
- `db/seed/` — development and test fixtures
- `docs/` — current architecture, gameplay, engineering, and operations docs
- `test/` — Node/TypeScript automated tests
- `server.js` — non-production compatibility/reference harness

## Local PostgreSQL

```bash
brew install postgresql@18
brew services start postgresql@18
createdb earth
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:migrate:postgres
DATABASE_URL=postgres://$USER@localhost:5432/earth npm run db:seed:dev
```

For the production-like local Worker path:

```bash
./scripts/migrate-local-db.sh --seed
DATABASE_READ_ONLY=false \
DATABASE_URL=postgres://earth:earth_dev_only@localhost:5432/earth \
npm run start:wrangler
```

The Flutter client should use the local Worker URL (normally
`http://localhost:8788`).

## World time and settlement

The authoritative world clock is PostgreSQL-backed.

At the canonical 1:60 time ratio:

- 1 real second = 1 game minute
- 1 real minute = 1 game hour
- 24 real minutes = 1 game day

The Worker scheduled handler performs bounded catch-up and ordered settlement.
Local scheduled-event testing is supported by the repository launcher and
`/__scheduled` test endpoint.

## Production client

```bash
cd flutter_client
flutter pub get
flutter run -d chrome --dart-define=EARTH_API_URL=https://earthuc.com
```

Release build:

```bash
flutter build web --release --base-href /
cd ..
npx wrangler deploy --config wrangler.api.jsonc
```

## Current V5 gameplay pillars

- House/Human continuity, mortality, succession, and inheritance
- Corporation membership, governance, public finance, and capacity economics
- Buildings, production, resources, construction, upgrades, and persistence
- Global Spot Market and auditable CREDIT/resource accounting
- Technology generations, research, adoption, patents/licenses where active
- Communities and communications
- EARTH/Corporation governance and constitutional rules
- Progressive physical-capacity economics
- Persistent daily settlement and world conditions

Territory is intentionally not a third political layer. Standardized Territory
containers are implementation/world-capacity context and should not be exposed
as routine management gameplay merely because records exist.

## Verification

Use current scripts from `package.json`.

Core checks include:

```bash
npm run db:verify:migrations
npm run db:verify:canonical
npm run test:certification
npm test
npm run cf:check
```

Flutter:

```bash
cd flutter_client
flutter analyze
flutter test
flutter build web --release --base-href /
```

## Documentation rule

Do not use deleted V2/V3/V4 gameplay documents as design authority. Git history
is available for archaeology, but current implementation must follow V5 plus
current schema/source/tests.
