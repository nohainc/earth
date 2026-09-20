# API maintenance rules

The API has one canonical name and route for each operation. Client methods must call the canonical route directly; aliases are not retained for renamed or removed features.

When changing an API:

1. Search `cloudflare/src`, `flutter_client/lib`, and `test` for the old route and method name.
2. Update the server handler and the typed client method together.
3. Remove obsolete callers and tests instead of adding compatibility wrappers.
4. Keep database functions and migrations aligned with the active route surface.
5. Add or update a focused behavior test, then run the API-surface check and the affected Flutter tests.

The API-surface regression test is `test/api-surface.test.mjs`. It protects canonical replacements and prevents retired aliases from being reintroduced during future changes.

Retired namespaces currently include public-investment share operations,
legacy Organization technology-adoption operations, human-level technology
subscriptions, manual clock mutation, dynasty aliases, and the successor
alias. Patent and licensing records remain settlement-owned V5 domain facts;
they have no player mutation endpoint in the legacy Organization namespace.
Corporation research, canonical technology access, and V5 Governance are the
active player-facing technology surfaces.
