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

Run the complete gate with `npm run qa`. Tier 2 is intentionally a Flutter
command because Flutter owns rasterization; CI should run it once with checked-in
goldens and fail on pixel drift.

## Invariants

The simulation suite asserts conservation of credits, non-negative balances and
resources, bounded machine condition, deterministic replay, and termination for
adversarial seeds. These are safety properties rather than expected-value tests.
