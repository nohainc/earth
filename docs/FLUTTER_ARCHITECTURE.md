# Flutter Client Architecture

## Decision

EARTH uses an incremental, feature-first Flutter modular monolith. The client
does not adopt Riverpod, code generation, or a generated API client yet. Those
options remain deferred until the DTO and error contract has stabilized and a
measurable benefit justifies the migration.

## Why this is the best current shape

`lib/main.dart` currently contains the application shell, transport client,
state models, authentication, command-center state, dashboard panels, and
action dialogs in one file. That was useful during the prototype phase, but a
4,000-line editing surface increases AI change risk: unrelated features are
easy to modify accidentally, context is expensive to load, and tests cannot
name feature boundaries clearly.

The selected structure keeps the existing runtime and verification gates while
creating small, discoverable ownership boundaries:

```text
lib/
  app/                 application shell, routing, theme
  core/
    api/               HTTP client, API errors, request identity
    models/            EarthState and transport DTOs
    nano_markup_helper.dart Nano Markup encoder/decoder with fallback support
  features/
    auth/              session bootstrap, sign-in, registration, recovery
    command_center/    state coordinator, dashboard composition, navigation
    market/            market panels and order actions
    governance/        proposals, voting, delegation, arbitration
    institutions/      cities, corporations, communities, services
    operations/        machines, production, technology, AI policies
    lifecycle/         succession, estates, history, rankings
  shared/
    widgets/            panel, metric, error, and reusable display primitives
```

The first extraction seams are `EarthApi` and `EarthState`, then authentication
and command-center composition. Each extraction must preserve the public app
entrypoint, Flutter analyzer/tests/build, and the Worker smoke suite. No file
move should combine with a behavior change unless the behavior is covered by a
focused test.

## Rules for AI-assisted changes

1. A feature change starts in its feature directory; `main.dart` should only
   compose the application.
2. API calls belong in `core/api`, not in widgets or dialogs.
3. Domain state is passed into widgets as immutable values; mutation remains in
   a feature coordinator/controller.
4. Reusable visual primitives belong in `shared/widgets` and must not know
   about PostgreSQL, routes, or feature-specific identifiers.
5. Every extracted boundary keeps or adds a focused test before the next move.
6. Keep the current hand-written DTOs until the canonical API/error contract is
   stable; introducing generators now would add churn without reducing risk.

## Migration sequence

1. Extract `EarthApi`, `EarthApiException`, and `EarthState` into `core/`.
2. Extract authentication into `features/auth/`.
3. Extract command-center state/navigation and shared widgets.
4. Split dashboard panels by domain, starting with market and governance.
5. Add feature-level widget tests and retain the full release gates.

This is a refactor plan, not a claim that the final directory structure is
already complete.
