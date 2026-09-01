# EARTH five-tier QA system

This directory is the quality gate for EARTH: United Corporations. The tiers are
deliberately independent so a fast ledger check can run on every change while
browser and visual checks can run in CI or release verification.

| Tier | Scope | Entry point |
| --- | --- | --- |
| 1 | Unit, ledger, balance and rule tests | `npm run qa:tier1` |
| 2 | Flutter golden snapshots for the command shell across six themes and three viewports | `flutter test --update-goldens test/qa_tier2_golden_test.dart` |
| 3 | Deterministic multi-agent invariant and chaos/fuzz tests | `npm run qa:tier3` |
| 4 | Flutter widget, responsive and accessibility interaction tests | `npm run qa:tier4` |
| 5 | Full-stack browser journey and API smoke tests | `npm run qa:tier5` |
| UI | Flutter web application against a live Worker API | `npm run test:ui` |

Run the complete gate with `npm run qa`. Tier 2 is intentionally a Flutter
command because Flutter owns rasterization; CI should run it once with checked-in
goldens and fail on pixel drift.

## Browser UI integration

`scripts/run-ui-tests.sh` is the direct shell entry point; `npm run test:ui`
runs the same command. It runs Playwright against an isolated Flutter web client and a
new local Wrangler Worker on fresh local ports every time. It never probes,
reuses, or stops an existing API or web-client process. The test runner stops
only the Worker and Flutter process it created.

Copy `.env.example` to the ignored `.env` file and set `EARTH_TEST_PASSWORD`,
or supply it through the CI secret store before running it. `EARTH_TEST_EMAIL`
defaults to `vitalii.noga@gmail.com`.
Use a dedicated test account and database: the authenticated journey exercises
real persistence. The suite starts one fresh browser session, signs in through
the visible Flutter identity screen using the same process as a real player,
runs all UI journeys in that session, signs out through the UI, and closes the
browser. Test failure artifacts and server logs are written to ignored Playwright
and `.test-artifacts` folders.

## Invariants

The simulation suite asserts conservation of credits, non-negative balances and
resources, bounded machine condition, deterministic replay, and termination for
adversarial seeds. These are safety properties rather than expected-value tests.
