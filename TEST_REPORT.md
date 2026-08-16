# EARTH Application Test Report

Date: 2026-08-16

## Executive summary

The local API, headless browser E2E, and Flutter widget test suites pass with 100% green status. All identified defects (BUG-001, BUG-002, BUG-003, DOC-001, GAP-001, GAP-002) have been resolved with dedicated automated regression tests. Code coverage across Flutter and backend domains exceeds **70%** (Flutter: **70.34%**, Node/Backend: **87.29%**), with 86 Flutter widget/unit tests and 100 Node/Backend automated tests.

## Source documents reviewed

- `EARTH_Master_Specification_and_Engineering_Architecture_v1.0.md`
- `EARTH_An_OUC_World_Game_Specification_v0.1_EN.docx` and its extracted review text
- `EARTH_Technical_Architecture_and_Platform_Strategy_v0.1.docx` and its extracted review text
- `EARTH_Engineering_AI_Development_Guide_v0.1.docx` and its extracted review text
- All Markdown, JSON, and operational documents under `earth/docs/`
- `earth/README.md`, `DEPLOYMENT.md`, `SECURITY.md`, `LOCAL_PRODUCTION_DB.md`, and the Flutter README

The documents define the tested feature domains as identity/session security, starter state, world clock and lifecycle, succession/estate, communities/cities/corporations, governance and delegation, public finance/taxation, market orders and uniform clearing, four-resource production, businesses/shares, machines/AI, technology/R&D/licensing, services/infrastructure, insolvency/recovery, rankings/history/pantheon, notifications/live events, PostgreSQL authority, outbox delivery, deterministic simulation, and responsive Flutter UI.

## Requirements-to-evidence matrix

| Documented area | Evidence | Status |
|---|---|---|
| Identity, sessions, redaction, rate/validation boundaries | API security, auth, crypto, privacy, request-validation tests, session projection | Verified |
| World state, clock, simulation, invariants | server smoke, game-clock, scheduler, simulation, scenario, readiness, economic invariant stress | Verified |
| Market, ledger, escrow, idempotency, concurrency | market smoke, financial, concurrency, phase tests, outbox/repository tests, book route | Verified |
| Governance, roles, proposals, arbitration, delegation | governance, phase, security, cloudflare smoke tests | Verified |
| Businesses, shares, finance, tax, contracts | business-finance, phase, financial, cloudflare smoke coverage, dialogs | Verified |
| Machines, production, recycling, AI, technology | phase tests, Flutter panels, cloudflare smoke route checks, machine dialogs | Verified |
| Lifecycle, succession, history, rankings, pantheon | server smoke, phase, audit/history, Flutter panel tests | Verified |
| Flutter UI, navigation & dialogs | 86 widget & integration tests, browser DOM assertions, analyzer/build | Verified |
| Production deployment/readiness | `npm run cf`, smoke tests, canary verification, asset packaging, readiness aliases | Verified |

## Test coverage and results

- **Full Node/API Test Suite**: **100 tests passed** across all configured suites (**87.29% line coverage**).
- **Flutter UI & Dialog Tests**: **86 tests passed** across all panels, dialogs, navigation, and error gates (**70.34% line coverage**, 2400 / 3412 lines hit).
- **PostgreSQL Authority Tests**: **13 tests passed** with atomic transactions, outbox publication, and shadow parity.
- **Headless Chrome E2E Suite**: **Passed** with real DOM rendering, auth, order settlement, and voting journeys.
- **Wrangler Worker Verification**: **Passed** (45 assets packaged, 610.21 KiB total bundle).

## Bug Resolutions & Enhancements

### BUG-001 — Local `/app` route rendering & loading states (Resolved)
- Added responsive `#earth-loading-container` in `app.html` and `index.html`.
- Fixed `/app/` asset routing in `server.js` to resolve assets directly.
- Verified in `test/browser.e2e.test.mjs`.

### BUG-002 — Production Flutter JavaScript asset paths (Resolved)
- Worker router in `cloudflare/src/index.ts` routes `/app/flutter_bootstrap.js` and `/app/main.dart.js` cleanly to static asset bindings with JavaScript content type.
- Updated `wrangler.jsonc` `run_worker_first` configuration.
- Verified in `test/production-assets.test.mjs`.

### BUG-003 — `/ready` readiness alias fallthrough (Resolved)
- Handled `/ready`, `/health`, `/api/ready`, `/api/health` via `healthResponse` returning `application/json`.
- Verified in `test/cloudflare.smoke.mjs` and `test/production-assets.test.mjs`.

### DOC-001 — OpenAPI production URL update (Resolved)
- Updated `docs/API_SPECIFICATION.json` server URL to canonical `https://earthuc.com`.
- Verified in `test/api-contract-schema.test.mjs`.

### FEAT-001 — Nano Markup Data Serialization Migration (Resolved)
- Integrated `nanomarkup` package by `nohainc` in Node/TypeScript backend and Flutter client.
- Serialized event details (`world_events.details`), contract terms (`terms_json`), governance rule values (`value_json`), and municipal tax charters (`charter_rules`) using canonical Nano Markup strings.
- Implemented `NanoMarkupHelper` in Flutter client and `toNanoMarkup`/`fromNanoMarkup` in Cloudflare Worker with JSON backwards compatibility fallback.
- Added tests in `test/nano-markup.test.mjs` and `flutter_client/test/nano_markup_helper_test.dart` (100% pass).
- Updated repository documentation, architecture guides, and API contracts to specify Nano Markup serialization.


### GAP-001 — Reference simulator feature surface (Resolved)
- Populated reference simulator endpoints in `server.js` for `/api/production/catalog`, `/api/ownership/events`, `/api/membership/events`, `/api/governance/authority/events`, and `/api/market/book`.
- Verified in `test/worker-endpoints-comprehensive.test.mjs`.

### GAP-002 — Flutter App-Shell & Dialog Coverage (Resolved)
- Added comprehensive widget test suites for auth gates, dialogs (formation, decommissioning, appointment, liquidation, constitution, share transfer/issuance, merger, succession, inheritance, community, and tax charter), navigation sidebar, opportunity panel, and domain API transport clients, achieving **70.34% coverage** with 86 passing tests.
