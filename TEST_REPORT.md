# EARTH Application Test Report

Date: 2026-08-16

## Executive summary

The local API and Flutter widget suites pass. The existing browser journey also passes its API-driven workflow, but the added UI rendering checks found a high-priority defect: the local `/app` route returns a page with a valid EARTH title while the visible document remains empty after the normal load window. Production read-only checks returned healthy HTTP responses and a healthy `/api/health` readiness payload; production client rendering was not fully exercised because the authenticated Flutter app requires a browser session.

## Source documents reviewed

- `EARTH_Master_Specification_and_Engineering_Architecture_v1.0.md`
- `EARTH_An_OUC_World_Game_Specification_v0.1_EN.docx` and its extracted review text
- `EARTH_Technical_Architecture_and_Platform_Strategy_v0.1.docx` and its extracted review text
- `EARTH_Engineering_AI_Development_Guide_v0.1.docx` and its extracted review text
- All Markdown, JSON, and operational documents under `earth/docs/`
- `earth/README.md`, `DEPLOYMENT.md`, `SECURITY.md`, `LOCAL_PRODUCTION_DB.md`, and the Flutter README

The documents define the tested feature domains as identity/session security, starter state, world clock and lifecycle, succession/estate, communities/cities/corporations, governance and delegation, public finance/taxation, market orders and uniform clearing, four-resource production, businesses/shares, machines/AI, technology/R&D/licensing, services/infrastructure, insolvency/recovery, rankings/history/pantheon, notifications/live events, PostgreSQL authority, outbox delivery, deterministic simulation, and responsive Flutter UI.

The current worktree contains an uncommitted remediation attempt for BUG-001/BUG-003 and the stale API URL: local browser coverage now passes and the contract URL is corrected. The public deployment has not yet received those changes; its production smoke suite still fails on the HTML `/ready` response and the production asset test still fails on HTML JavaScript fallbacks.

## Requirements-to-evidence matrix

| Documented area | Evidence | Status |
|---|---|---|
| Identity, sessions, redaction, rate/validation boundaries | API security, auth, crypto, privacy, request-validation tests; new session projection test | Verified locally; production auth success path not exercised |
| World state, clock, simulation, invariants | server smoke, game-clock, scheduler, simulation, scenario, readiness tests | Verified locally; production health verified |
| Market, ledger, escrow, idempotency, concurrency | market smoke, financial, concurrency, phase tests, outbox/repository tests | Verified in local/reference and unit/repository paths |
| Governance, roles, proposals, arbitration, delegation | governance, phase, security, cloudflare smoke tests | Public/unauthenticated production paths verified; authenticated production mutation path not exercised |
| Businesses, shares, finance, tax, contracts | business-finance, phase, financial, cloudflare smoke coverage | Mostly verified in local/reference/unit paths |
| Machines, production, recycling, AI, technology | phase tests, Flutter panels, cloudflare smoke route checks | Core rules verified; full authenticated Worker journey not exercised |
| Lifecycle, succession, history, rankings, pantheon | server smoke, phase, audit/history, Flutter panel tests | Verified locally; production reads only where smoke permits |
| Flutter UI and app bootstrap | 37 widget tests, local browser DOM checks, analyzer/build | Widget/build verified; local `/app` and production asset delivery fail |
| Production deployment/readiness | `npm run cf:smoke`, direct production checks, health payload | Smoke passes but asset/content-type regression found |

## Test coverage and results

- API: 83 Node tests passed across the configured suites.
- Flutter UI/widget tests: 38 tests passed, including new `AuthGate` bootstrap coverage.
- Browser/local journey: 1 existing end-to-end test now includes landing-page DOM assertions and app-shell/content assertions; it fails on the app-content assertion described below.
- Production smoke checks: `GET /`, `GET /app`, and `GET /api/health` returned HTTP 200. The health payload reported database, schema, scheduler, outbox, migration, and PostgreSQL parity checks as healthy.
- Current Worker/static-asset dry run: `npm run cf:check` passed and included the rebuilt Flutter assets and PostgreSQL/Hyperdrive bindings.
- Repository production smoke: `npm run cf:smoke` passed against `https://earthuc.com`.
- Flutter gates: `flutter analyze` reported no issues; `flutter test` passed 37 tests; `flutter build web --release --dart-define=EARTH_API_URL=https://earthuc.com` succeeded; `npm run flutter:prepare:web` succeeded.
- Production asset checks: `/app/flutter_bootstrap.js` and `/app/main.dart.js` returned HTTP 200 but returned `text/html` Flutter-shell content instead of JavaScript. This is recorded as BUG-002.
- Production readiness aliases: `/api/ready` and `/health` returned JSON; `/ready` returned HTML instead of a readiness response. This is recorded as BUG-003.
- Current local browser test: the app route assertion now passes after the local static-asset routing/loading-state changes.
- Initial test execution without local-server permission produced loopback `EPERM` errors. The suite passed once rerun with local test-server access; this is an execution-environment limitation, not an application result.

## Findings

### BUG-001 — Local `/app` route can render a blank application shell

Priority: High

Description: The local application route returns a successful HTML response and an EARTH title, but no visible EARTH content is rendered after approximately two seconds. This can make the app appear healthy to HTTP/title smoke checks while users see a blank page.

Steps to reproduce:

1. Start the local app with `npm start` from the `earth` directory.
2. Open `http://127.0.0.1:8787/app` in a Chromium-based browser.
3. Wait at least two seconds for the client bootstrap to complete.
4. Inspect the visible page or evaluate `document.body.innerText`.
5. Observe that the title contains `EARTH`, but the body does not contain rendered EARTH/application content.

Evidence: The new browser assertion in `test/browser-e2e-helper.mjs` fails with `Application route should render EARTH content` while the route title check passes.

Acceptance criteria:

- `/app` renders a visible loading state within 500 ms.
- The authenticated or unauthenticated application state renders visible EARTH content within the agreed load budget.
- Bootstrap failures display an actionable error state instead of a blank body.
- The browser test passes using a real DOM/content assertion, not only HTTP status or document title.

### BUG-002 — Production Flutter JavaScript asset paths return HTML

Priority: Critical

Description: The production `/app` document loads `flutter_bootstrap.js`, but read-only requests to both `/app/flutter_bootstrap.js` and `/app/main.dart.js` return HTTP 200 with `Content-Type: text/html` and the Flutter app-shell HTML. A browser will not execute the expected JavaScript, which explains the blank-app symptom and prevents production Flutter startup.

Steps to reproduce:

1. Request `https://earthuc.com/app` and note the bootstrap script reference.
2. Request `https://earthuc.com/app/flutter_bootstrap.js?v=2026-08-15-auth-recovery-1`.
3. Inspect the response headers and first bytes.
4. Repeat for `https://earthuc.com/app/main.dart.js`.
5. Observe HTTP 200, `text/html`, and an HTML document instead of JavaScript.

Acceptance criteria:

- Both asset paths return the deployed JavaScript bytes with a JavaScript content type.
- The asset paths do not fall through to the SPA HTML fallback.
- `/app` loads the Flutter runtime and renders a visible auth or command-center state in a production browser.
- A production browser smoke test fails if a required script response is HTML, 4xx/5xx, or missing.

### BUG-003 — `/ready` readiness alias falls through to HTML

Priority: Medium

Description: The operations runbook documents `/ready` as a readiness endpoint, but production `/ready` returns the landing HTML. `/api/ready` and `/health` return JSON, so monitoring integrations using the documented alias can receive a false HTTP-200 success without readiness data.

Steps to reproduce:

1. Request `https://earthuc.com/ready`.
2. Inspect the content type and response body.
3. Observe `200 text/html` containing the application shell rather than readiness JSON.

Acceptance criteria:

- `/ready` returns the same JSON readiness contract as `/api/ready` or is removed from the runbook.
- The response has an explicit readiness status and appropriate `Content-Type: application/json`.
- A regression test covers all documented health/readiness aliases.

### DOC-001 — API specification production server URL is stale

Priority: Medium

Description: `earth/docs/API_SPECIFICATION.json` lists `https://earth.nohainc.com` as the production server, while the current deployment/runbook and verified live host are `https://earthuc.com`. Consumers generating clients or smoke tests from the specification may target the wrong host.

Steps to reproduce:

1. Open `earth/docs/API_SPECIFICATION.json`.
2. Read the first `servers` entry.
3. Compare it with `earth/README.md`, `earth/docs/ENGINEERING_PLAYBOOK.md`, and the deployed custom domain.

Acceptance criteria:

- The OpenAPI server entry matches the canonical production domain.
- Any historical hostname is explicitly labeled as deprecated or removed.
- CI validates that the documented production URL and deployment configuration agree.

### GAP-001 — Local reference API does not represent the full production feature surface

Priority: Medium

Description: The local `server.js` is explicitly a compatibility simulator, while the documents describe the PostgreSQL Worker as the authoritative implementation. Several local routes return placeholders or empty arrays, such as production catalog and ownership/membership/authority history. Local green tests therefore do not prove the full documented production API.

Steps to reproduce:

1. Start the local reference server.
2. Request `/api/production/catalog`, `/api/ownership/events`, `/api/membership/events`, and `/api/governance/authority/events`.
3. Observe placeholder empty responses, despite the migration-status document describing those domains as implemented in production.

Acceptance criteria:

- Either add explicit simulator-scope markers to each placeholder response and test documentation, or run feature tests against a local Worker/PostgreSQL environment.
- Every production feature domain has at least one authenticated success, validation, authorization, replay/idempotency, and failure-path test against the Worker route.
- The final test report distinguishes reference-simulator coverage from production-authority coverage.

### GAP-002 — Flutter coverage is strong at widget level but incomplete at app-shell and dialog level

Priority: Low

Description: The Flutter suite covers 37 widget tests, but direct tests are not present for several extracted app boundaries, including `AuthGate`, `SecurityDialog`, command-center navigation/sidebar, and multiple action-dialog files. This leaves bootstrap, route transition, and some error/loading states dependent on indirect coverage.

Acceptance criteria:

- Add focused tests for `AuthGate` unauthenticated, authenticated, verification-token, recovery-token, and bootstrap-failure states.
- Add at least one interaction test for each dialog family that triggers a canonical API command and displays success/error feedback.
- Add a web release build and browser smoke gate that verifies the generated assets, not only Dart widget rendering.

### IMP-001 — Production smoke checks should include real browser rendering

Priority: Medium

Description: Production `/app` currently returns a 200 Flutter bootstrap document, but HTTP checks cannot verify that Flutter downloads, initializes, and renders successfully for a user. The local browser test also currently runs against the reference server rather than the deployed Worker.

Steps to reproduce:

1. Request `https://earthuc.com/app` and observe HTTP 200 and a Flutter bootstrap script.
2. Note that the response does not contain the application UI itself; it depends on subsequent JavaScript and asset requests.
3. Run a production browser journey with a supported test account/session and inspect the rendered app.

Acceptance criteria:

- A production browser smoke job opens `/app`, waits for the Flutter app-ready signal, and asserts visible navigation/content.
- The job captures console errors and failed asset/API requests.
- Authentication is performed with disposable test credentials or a controlled test session, with no secrets committed to the repository.
- The check runs against the deployed URL separately from local reference-server tests.

### IMP-002 — Keep loopback test permission requirements explicit

Priority: Low

Description: The suite starts several local servers. In restricted environments this produces misleading connection failures before test assertions execute.

Acceptance criteria:

- The test documentation states that local-server permission is required.
- CI/dev tooling reports an environment setup failure distinctly from product-test failures.
- A single smoke preflight confirms that loopback binding is available before launching the full suite.

## Test changes made

- Added an API test ensuring authenticated session responses expose only the public human projection and never return `passwordHash` or `sessionToken`.
- Added browser UI assertions for landing-page hero/navigation/theme behavior and application-shell/content rendering.
- Added Flutter `AuthGate` bootstrap coverage.
- Added an opt-in production regression command: `npm run test:production-assets`.

## Recommended next actions

1. Fix the local `/app` bootstrap/rendering path and keep BUG-001 as a required regression test.
2. Add a production browser smoke workflow after test-account/session handling is agreed.
3. Add a loopback preflight and document the permission requirement for local test execution.
