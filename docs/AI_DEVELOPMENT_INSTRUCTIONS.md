# EARTH AI development instructions

This document is the operating guide for future AI-assisted work on EARTH. It
combines the repository decisions in
[`ADR-001-current-architecture-boundary.md`](ADR-001-current-architecture-boundary.md)
and [`FLUTTER_ARCHITECTURE.md`](FLUTTER_ARCHITECTURE.md). The master
specification remains authoritative when these instructions are ambiguous.

## 1. Start every task with evidence

Before editing:

1. Read the relevant sections of
   `EARTH_Master_Specification_and_Engineering_Architecture_v1.0.md`.
2. Read the applicable architecture document and current ADRs.
3. Inspect the current source, migrations, tests, and deployment configuration.
4. Check `git status`; preserve unrelated user changes.
5. Identify the exact public route, database tables, client screens, and tests
   affected by the task.
6. State whether the work is current architecture, target architecture, or a
   new decision requiring an ADR.

Never describe a target recommendation as implemented without repository,
deployment, and verification evidence.

## 2. Choose the smallest complete vertical slice

Implement one bounded user journey or domain capability at a time. A complete
slice normally includes:

- Worker route and validation;
- domain rule or repository operation;
- PostgreSQL migration when schema changes are required;
- ledger, history, and outbox records for authoritative mutations;
- Flutter API method and feature UI state;
- focused success, validation, authorization, replay, and failure tests;
- production smoke coverage when the public contract changes.

Do not solve a large refactor and a behavior change in the same edit unless the
new behavior has focused coverage.

## 3. Non-negotiable authority rules

- PostgreSQL is the only production authority.
- The Flutter client is an untrusted presentation shell.
- Never trust client balances, taxes, market fills, production results,
  ownership, governance outcomes, or game time.
- Durable Objects coordinate sockets and delivery; they do not own economic
  state.
- Never put authoritative state in module-level mutable memory.
- Money, ownership, inventory, legal status, and game-time changes require one
  short atomic PostgreSQL transaction.
- Ledger entries, ownership events, membership events, authority events, and
  world history are append-only. Correct mistakes with compensating entries.
- External delivery, email, WebSocket broadcast, and unbounded work happen
  after commit, never inside the economic transaction.

## 4. TypeScript Worker rules

### File ownership

Keep HTTP concerns in the Worker boundary:

- authentication and actor resolution;
- authorization and institution scope;
- runtime input validation;
- idempotency mapping;
- command/query dispatch;
- stable DTO and error normalization.

Keep business rules and PostgreSQL operations in bounded-context modules under
`cloudflare/src/`. Prefer the existing context names: `auth`, `market`,
`governance`, `institutions`, `finance`, `lifecycle`, `machines`,
`technology`, `scheduler`, and read projections.

Do not add new domain logic to `index.ts` when a context module is appropriate.
Keep `index.ts` as compatibility route glue until an extraction is verified.

### Command sequence

For every state-changing command:

1. Authenticate first.
2. Parse the body through the runtime validation layer.
3. Resolve `Idempotency-Key`; temporarily accept matching body
   `correlationId`; reject conflicts.
4. Load the current game clock and active rule version.
5. Start one PostgreSQL transaction.
6. Lock contested rows in deterministic order.
7. Re-check mutable authorization and balances inside the transaction.
8. Apply the rule and all ledger/history changes.
9. Write the outbox event in the same transaction.
10. Commit, then perform external delivery.

Malformed JSON is a validation error, not a 503. Public errors must contain a
safe message, stable `code`, and `correlationId`; never expose SQL, provider
details, stack traces, or secrets.

### Determinism and money

- Keep pure calculations independent of `Request`, Cloudflare APIs, database
  I/O, wall-clock time, and random values.
- Pass game time explicitly into deterministic rules.
- Never use JavaScript floating-point arithmetic for authoritative money.
- Use the existing money helpers and PostgreSQL numeric/account primitives.
- Add adversarial tests for insufficient funds, replay, contention,
  serialization/deadlock retry, and rollback/no-partial-write behavior.

## 5. Flutter rules

Use the incremental feature-first modular monolith:

```text
lib/
  app/                 shell, routing, theme
  core/api/            transport, errors, API facade
  core/models/         immutable state and DTOs
  features/auth/
  features/command_center/
  features/market/
  features/governance/
  features/institutions/
  features/operations/
  features/lifecycle/
  shared/widgets/      reusable presentation primitives
```

- Put API calls in `core/api`, never directly in widgets or dialogs.
- Keep feature state in a coordinator/controller, not in reusable widgets.
- Pass immutable values into widgets.
- Keep shared widgets independent of routes, PostgreSQL, and domain IDs.
- Keep `main.dart` as composition and compatibility glue; extract one cohesive
  feature at a time.
- Preserve the hand-written DTOs and transport until the API/error contract is
  stable. Do not introduce Riverpod, code generation, or generated clients
  without an ADR and measurable benefit.
- Financial and voting actions show loading until server confirmation;
  optimistic updates are for local visual state only.

### 5.1 EARTH typography system

Use the shared Flutter typography tokens in `lib/app/theme.dart` instead of
creating one-off menu text styles.

- Primary UI font: `Manrope` through `createEarthTheme`.
- Menu/navigation text: `13px`, weight `500`, letter spacing `0.7px`,
  color `mutedColor` (`#9698B5`).
- Active menu text: the same token with weight `700` and `inkColor`
  (`#F1F0FF`).
- Menu group labels: `8.5px`, weight `700`, letter spacing `1.3px`,
  uppercase, `mutedColor`.
- Keep menu icons aligned with their text and use the same normal/active color
  rules. Reserve red for destructive actions such as Sign out.
- Avoid using wide tracking such as `1.3px` for normal sentence-case menu
  items; it makes labels unnecessarily wide. Use `1.3px` primarily for compact
  uppercase labels and telemetry/technical readouts.
- Do not introduce another font or local font size without a UI/UX reason;
  update the shared token when the system changes.

### Page layout standards

- Use a two-column content layout when the available page content width is
  greater than `1000px`; keep the same content in one vertical column below
  that breakpoint.
- Use one shared topic-heading style throughout a page. The page title and
  section titles must use the same font family, size, weight, color, and
  letter spacing.
- Place a topic help icon immediately after its title, not at the far edge of
  the header. The icon opens the topic-specific explanation.
- Use a horizontal separator only when it communicates a real boundary between
  control groups. Do not add separators when spacing and heading hierarchy are
  sufficient.
- Prefer the shared page shell and spacing tokens. Remove an outer shell only
  when the page content itself already provides clear grouping and the extra
  border reduces usable space.
- Treat the first visible topic as the page identity; do not add a second,
  competing page-title bar above it.
- Use a consistent topic rhythm: `34px` before subsequent topic headings and
  `10px` between a heading and its controls. The first topic in a column may
  use zero top offset when it aligns with the first topic in another column.
- Topic content should stretch to the column width and align to the left edge;
  do not rely on Flutter's default centered `Column` alignment.
- Keep the first topic focused on its primary controls. Avoid wrapping it in a
  redundant parent card when the controls already provide visual grouping.
- For wide pages, align the first topic heading and first control in both
  columns on the same baseline; for narrow pages, restore the normal topic
  spacing in the single vertical flow.

### Group surface standard

- The page background is the active theme canvas. Standard grouped controls,
  widgets, and content cards use the active theme card surface as a solid,
  fully opaque fill, with `EarthColors.borderSubtle` and an 8px radius.
- Do not use fixed default-blue surface constants or arbitrary alpha values
  for standard groups: they break theme consistency and make matching widgets
  appear to have different backgrounds.
- Reserve tinted fills and non-standard borders for semantic states only:
  selected, unread, warning, success, error, or a meaningful domain status.
- Do not add a nested card merely for decoration. Use a border or spacing
  unless the nested content is independently actionable.

## 6. Database and migration rules

- Treat `db/schema.sql` and `db/schema-manifest.json` as the authoritative current
  canonical schema. `db/schema.sql` describes the clean, full database state from
  scratch and must be updated alongside any new schema migration.
- Add every schema change as a forward-only, human-reviewed SQL migration under
  `db/migrations/` using the next available version number (e.g. `081_...`).
- Update `db/schema.sql` and `db/schema-manifest.json` when the schema contract changes.
- Never use destructive automatic schema pushes in production.
- Add indexes for foreign keys, active-state lookups, and timestamp filters.
- Put invariants in PostgreSQL constraints where practical.
- Use stored functions only for narrow atomic primitives under contention.
- Never silently edit historical records or create credits by overwriting a
  balance.
- Apply and verify migrations locally before production.

## 7. Testing and verification gate

- **Minimum Test Coverage Requirement (80% Line Coverage)**: All codebase modules (Dart/Flutter client and TypeScript/Node backend) must maintain at least **80% automated test coverage** (`LF`/`LH` lines covered $\ge 80.0\%$). New features and refactors must include unit and widget/integration tests to ensure total coverage remains at or above 80%.

Run the smallest relevant tests during development, then the full gate before
handoff:

```text
npm test
npm run cf:check
cd flutter_client && flutter analyze
cd flutter_client && flutter test --coverage
cd flutter_client && flutter build web --release --base-href /
npm run flutter:prepare:web
npm run cf:smoke
```

For money, ownership, governance, lifecycle, or scheduler work, also verify:

- PostgreSQL authority and mutation boundaries;
- migration and manifest checks;
- balances plus ledger/history/outbox records;
- replay and authorization behavior;
- production readiness checks;
- one monitored game-day tick;
- the changed user journey manually.

Tests are evidence only when they cover the requirement being claimed.

## 8. Simulation Time Model & Actuarial Mortality Engine

- **Canonical Time Dilation (1:60 Ratio)**:
  - `1 Real Second = 1 Simulation Game Minute`.
  - `60 Real Seconds (1 Real Minute) = 1 Simulation Game Hour`.
  - `24 Real Minutes = 1 Simulation Game Day (24 Game Hours / 1,440 Game Minutes)`.
  - `1 Real Day (24 Real Hours) = 60 Simulation Game Days (2 Game Months)`.
  - `6 Real Days (144 Real Hours) = 360 Simulation Game Days (1 Game Year)`.
  - `6.08 Real Days = 365 Simulation Game Days (1 Solar Game Year)`.
  - **Natural Character Lifespan**: Characters enter at legal adulthood (Age 20) and have an actuarial life expectancy of 75–90+ simulation years (~55–70 simulation years of active play = **~330–425 Real Days / ~1 Real Year**).

- **Biometric Health & Stochastic Actuarial Mortality**:
  - **Health Impact (0–100%)**: Affects physical labor throughput, machine maintenance speed, corporate executive stamina, and periodic medical costs.
  - **Non-Linear Mortality**: Mortality is **not** a deterministic countdown to 0% health. Citizens can live long lives with sub-optimal or chronic health conditions (30–60%).
  - **Stochastic Actuarial Hazard**: Past retirement age (65+), an annual probabilistic hazard roll (Gompertz-Makeham curve) determines mortality risk. Lower health increases the annual hazard rate, while advanced municipal healthcare, high vitality, and clean environment increase longevity (up to 95–100+ simulation years).

## 9. Deployment and commits

- Keep commits focused and reversible.
- Commit major vertical slices separately from unrelated cleanup.
- Push verified commits regularly, as requested by the project owner.
- Deploy production only after local gates pass.
- After deployment, check the real `earthuc.com` health endpoint and smoke
  suite, not only a dry-run.
- If readiness fails, inspect scheduler/outbox diagnostics and Worker logs
  before making additional changes.
- Do not hide a failed production check in the final report.
- Never include database connection strings, tokens, or provider credentials in
  source, commits, logs, or responses.

## 10. When an ADR is required

Stop and write or amend an ADR before:

- changing PostgreSQL authority;
- adding Hono, Zod, Drizzle, Riverpod, OpenAPI generation, Queues, or R2;
- changing the game-clock model;
- changing Durable Object authority boundaries;
- renaming immutable UC/OUC identifiers;
- adding monetized gameplay mechanics;
- splitting a bounded context into an independently deployed service.

The ADR must state the problem, alternatives, migration plan, rollback plan,
operational cost, and verification evidence.

## 11. Final handoff format

Every completed AI task should report:

1. What changed and why it follows the specification.
2. Which files, migrations, routes, and features changed.
3. Tests and verification commands that passed.
4. Commit hash and deployment version, if deployed.
5. Any known incomplete target or deferred decision.

Do not claim the full project is complete when only one slice or architecture
boundary has been implemented.
