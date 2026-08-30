# EARTH AI File Map

This document is a quick orientation map for future AI-assisted changes.
It identifies which files are authoritative, which files are compatibility or
prototype-only, and where to begin for common feature requests.

## Authority order

Use this order when sources appear to overlap:

1. `cloudflare/src/` — authoritative Worker API and PostgreSQL-backed domain logic.
2. `flutter_client/lib/` — current application UI and client API integration.
3. `db/migrations/` — authoritative PostgreSQL schema.
4. `db/seed.sql` — canonical starter and local test data.
5. `test/` and `flutter_client/test/` — executable behavior and UI expectations.
6. `server.js` — non-production local reference simulator and compatibility API.
7. Root-level prototype files — legacy visual prototypes; do not treat them as the production application.

## Repository layout

| Path | Purpose | Authority |
|---|---|---|
| `cloudflare/src/` | Cloudflare Worker, API routes, PostgreSQL domain services, engines, and read models | Production backend |
| `flutter_client/lib/` | Flutter application, screens, panels, dialogs, models, and API clients | Current frontend |
| `db/migrations/` | Numbered PostgreSQL schema migrations | Database schema |
| `db/seed.sql` | Idempotent starter world and local UI/API fixtures | Seed data |
| `scripts/` | Migration, seeding, verification, build, deployment, and local-run helpers | Operations |
| `test/` | Node.js API, domain, integration, and contract tests | Backend behavior |
| `flutter_client/test/` | Flutter widget, golden, accessibility, and UI tests | Frontend behavior |
| `docs/` | Architecture, API, operations, security, and development guidance | Project guidance |
| `static-site/` | Static landing-site assets used by the Worker | Static web surface |
| Root-level `prototype*.{html,js,css}` | Earlier visual prototypes | Legacy/demo only |

## Backend map

### Entry points and shared infrastructure

| File | Responsibility |
|---|---|
| `cloudflare/src/index.ts` | Worker entry point, route dispatch, authentication boundary, and bindings |
| `cloudflare/src/repository.ts` | Repository abstraction and PostgreSQL authority selection |
| `cloudflare/src/postgres.ts` | PostgreSQL connection/query support |
| `cloudflare/src/read-postgres.ts` | Shared read models, rankings, institutions, archive, history, and public reads |
| `cloudflare/src/world-postgres.ts` | Canonical world snapshot and player state assembly |
| `cloudflare/src/health.ts` | Health, readiness, invariant, and database status responses |
| `cloudflare/src/request-validation.ts` | Request parsing, validation, and idempotency keys |
| `cloudflare/src/money.ts` | Credit and monetary arithmetic rules |
| `cloudflare/src/nano-markup.ts` | Nano Markup serialization helpers |
| `cloudflare/src/app-assets.ts` | Authenticated application asset serving |
| `cloudflare/src/static-assets.ts` | Static and landing-site asset serving |

### Route files

Route files generally validate HTTP requests and delegate business logic to the
matching PostgreSQL service.

| Feature | Routes |
|---|---|
| Authentication | `auth-public-routes.ts`, `auth-routes.ts`, `auth-session.ts` |
| Businesses | `business-routes.ts` |
| Cities and corporations | `institutions-routes.ts` |
| Communities | `community-routes.ts` |
| Contracts | `contract-routes.ts` |
| Dynasty | `dynasty-routes.ts` |
| Finance | `finance-routes.ts` |
| Governance | `governance-routes.ts` |
| Lifecycle and archive | `lifecycle-routes.ts` |
| Market | `market-routes.ts` |
| Real estate | `real-estate-routes.ts` |
| Social gameplay | `social-gameplay-routes.ts` |
| Technology | `technology-routes.ts` |

### PostgreSQL domain services

| Feature | Main files |
|---|---|
| Authentication and email actions | `auth-postgres.ts`, `auth-crypto.ts`, `admin-deliveries-postgres.ts` |
| Businesses and finance | `business-postgres.ts`, `business-finance.ts`, `financial-postgres.ts`, `finance-postgres.ts` |
| Cities and corporations | `institutions-postgres.ts`, `roles-postgres.ts` |
| Communities | `communities-postgres.ts` |
| Contracts and disputes | `contracts-postgres.ts`, `supply-contracts-postgres.ts`, `arbitration-postgres.ts` |
| Dynasty and lineage | `dynasty-postgres.ts` |
| Governance | `governance-postgres.ts` |
| Lifecycle, succession, and death | `lifecycle-postgres.ts` |
| Machines and production | `machines-postgres.ts`, `machines-recycling-postgres.ts`, `production-catalog.ts` |
| Market and derivatives | `market-postgres.ts`, `derivatives-postgres.ts`, `market-rules.ts` |
| Real estate and buildings | `real-estate-postgres.ts`, `real-estate-catalog.ts` |
| Social gameplay and communications | `social-gameplay-postgres.ts`, `communications-postgres.ts` |
| Technology and patents | `technology-postgres.ts` |
| Notifications and outbox | `outbox-postgres.ts`, `daily-briefing-postgres.ts` |
| Rankings and net worth | `net-worth-postgres.ts`, `read-postgres.ts` |

### Simulation and scheduled engines

The files under `cloudflare/src/engines/` implement settlement or simulation
subsystems. Start with the named engine before changing scheduler orchestration.

| File | Responsibility |
|---|---|
| `engines/simulation-orchestrator.ts` | Coordinates simulation phases |
| `engines/time-engine.ts` | Game-clock progression |
| `engines/financial-engine.ts` | Financial settlement |
| `engines/institutions-engine.ts` | City and corporation effects |
| `engines/lifecycle-engine.ts` | Human lifecycle and succession |
| `engines/market-engine.ts` | Market processing |
| `engines/production-engine.ts` | Production and machine output |
| `engines/resource-flow-engine.ts` | Resource movement and balances |
| `engines/rankings-engine.ts` | Ranking calculation |
| `engines/technology-engine.ts` | Research and technology effects |
| `scheduler-postgres.ts` | Persistent scheduled settlement and recovery controls |

## Flutter application map

| Path | Responsibility |
|---|---|
| `flutter_client/lib/main.dart` | Flutter process entry point |
| `flutter_client/lib/app/earth_app.dart` | Root application widget and navigation shell |
| `flutter_client/lib/app/theme.dart` | Theme controller and visual theme |
| `flutter_client/lib/core/api/` | API clients grouped by backend feature |
| `flutter_client/lib/core/models/` | Shared client-side state and DTO models |
| `flutter_client/lib/core/auth_storage*` | Cross-platform auth token storage |
| `flutter_client/lib/earth_http_client*` | Platform-specific HTTP transport |
| `flutter_client/lib/shared/design_system/` | Reusable visual primitives and layout components |
| `flutter_client/lib/shared/widgets/` | Reusable dialogs, cards, and formatting widgets |
| `flutter_client/lib/features/` | Feature-specific screens, panels, dialogs, and controllers |

### Flutter feature locations

| Feature | API client | UI directory |
|---|---|---|
| Activity | `earth_api_world.dart` | `features/activity/` |
| Authentication | `earth_api_auth.dart` | `features/auth/` |
| Command center | `earth_api_world.dart`, `earth_api_briefing.dart` | `features/command_center/` |
| Communities | `earth_api_comm.dart` | `features/institutions/institutions_panels.dart`, `features/institutions/institutions_dialogs.dart`, and `features/communications/` where the surface is social/communication-oriented |
| Corporations and cities | `earth_api_institutions.dart` | `features/institutions/` |
| Contracts | `earth_api_contracts.dart`, `earth_api_supply_contracts.dart` | `features/contracts/` |
| Dynasty | `earth_api_dynasty.dart` | `features/dynasty/` |
| Finance | `earth_api_personal_finance.dart`, `earth_api_net_worth.dart` | `features/finance/` |
| Governance | `earth_api_governance.dart` | `features/governance/` |
| Lifecycle and archive | `earth_api_lifecycle.dart`, `earth_api_world.dart` | `features/lifecycle/` |
| Market | `earth_api_market.dart`, `earth_api_derivatives.dart` | `features/market/` |
| Operations and businesses | `earth_api_business.dart`, `earth_api_machines.dart` | `features/operations/` |
| Real estate | `earth_api_real_estate.dart` | `features/operations/` |
| Research and patents | `earth_api_technology.dart` | `features/operations/` |

When a feature directory is not an exact match for the API client name, inspect
`earth_app.dart`, the relevant panel/dialog, and existing tests before creating
new files. Some cross-cutting pages intentionally live in `command_center/`
or `lifecycle/`.

## Database map

| Path | Responsibility |
|---|---|
| `db/schema.sql` | Authoritative canonical schema (tables, constraints, indexes) from scratch |
| `db/functions.sql` | Stored functions, procedures, and triggers (`earth_transfer_credits`, etc.) |
| `db/migrations/*.sql` | Forward-only, numbered SQL migrations (001 through 080+) |
| `db/schema-manifest.json` | Expected schema/table manifest |
| `db/seed.sql` | Starter world plus namespaced local test fixtures |

Migration files are append-only. Do not edit an applied migration; create a
new numbered migration and update `db/schema.sql` / `db/functions.sql` when the schema changes.

## Scripts and local development

| File or command | Use |
|---|---|
| `scripts/migrate-postgres.mjs` | Apply numbered migrations to an explicit PostgreSQL URL |
| `scripts/seed-postgres.mjs` | Apply `db/seed.sql` transactionally and idempotently |
| `scripts/migrate-local-db.sh` | Prepare the local PostgreSQL database |
| `scripts/run-local-ui-test.sh` | Start local Worker API and Flutter Chrome client |
| `scripts/start-local-production-db.mjs` | Start the guarded local production-style reference server |
| `scripts/verify-schema-manifest.mjs` | Verify expected database schema |
| `scripts/verify-postgres-invariants.mjs` | Verify balances, machine bounds, scheduler, and data invariants |
| `npm run start:wrangler` | Run the local Worker API on port 8788 |
| `npm run db:migrate:postgres` | Run PostgreSQL migrations |
| `npm run db:seed:postgres` | Seed the local or explicitly supplied database |
| `npm run qa:<feature>` | Run focused feature QA suites |

The normal local UI path is the Flutter client against the Worker API. The
Node `server.js` simulator is useful for compatibility and automated tests but
is not the canonical production-like application path.

## Tests

Backend feature tests are in `test/`. Names usually identify the page or domain,
for example `communities-postgres.test.mjs`, `institutions-postgres.test.mjs`,
`memorial-page-api.test.mjs`, and `dynasty-page-api.test.mjs`.

Flutter widget and UI tests are in `flutter_client/test/`. Look for the feature
panel name first, then broader accessibility, golden, or comprehensive suites.

Before changing behavior:

1. Find the closest page/API test.
2. Find the matching route and PostgreSQL service.
3. Find the Flutter API client and panel/dialog.
4. Update or add tests at the same layer as the behavior change.

## Legacy and compatibility files

The following files are valuable for visual comparison but should not normally
be changed for current app behavior:

- Root `prototype2.html`, `prototype2.js`, and `prototype2.css`.
- Root `prototype3.html`, `prototype3.js`, and `prototype3.css`.
- Root `app.js`, `index.html`, and `styles.css`.
- `earth/server.js` and `earth/simulation.js` when the request concerns the
  authoritative Worker or Flutter application.

Check links and README instructions before deleting or moving any of these;
they may still be used for demos, review, or compatibility tests.

## Quick lookup rules for future AI changes

- “Add or change an API endpoint”: inspect `cloudflare/src/index.ts`, the
  matching `*-routes.ts`, matching `*-postgres.ts`, and the nearest `test/` file.
- “Change a page or panel”: inspect the matching Flutter feature directory, its
  `earth_api_*.dart` client, and the nearest Flutter test.
- “Add test data”: inspect the relevant migration columns and append an
  idempotent block to `db/seed.sql`; use a namespaced `TEST-*` ID.
- “Change a table or relationship”: inspect the latest related migration and
  create a new migration; update seed data and schema verification as needed.
- “Change settlement or simulation”: inspect the relevant engine plus
  `scheduler-postgres.ts` and invariant tests.
- “Change authentication or permissions”: inspect auth/session code, route
  guards, roles/authority services, and security tests before UI code.
- “Change deployment or local startup”: inspect the relevant Wrangler config,
  `README.md`, `LOCAL_PRODUCTION_DB.md`, and scripts before modifying code.

## Naming guidance

Do not rename files solely to make this map cleaner. The repository contains
legacy prototypes, compatibility code, and production-style code side by side;
the distinction is more important than uniform naming. Update this map when a
new feature area or authoritative entry point is introduced.
