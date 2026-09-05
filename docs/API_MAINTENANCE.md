# API maintenance rules

The API has one canonical name and route for each operation. Client methods must call the canonical route directly; aliases are not retained for renamed or removed features.

When changing an API:

1. Search `cloudflare/src`, `flutter_client/lib`, and `test` for the old route and method name.
2. Update the server handler and the typed client method together.
3. Remove obsolete callers and tests instead of adding compatibility wrappers.
4. Keep database functions and migrations aligned with the active route surface.
5. Add or update a focused behavior test, then run the API-surface check and the affected Flutter tests.

The API-surface regression test is `test/api-surface.test.mjs`. It protects canonical replacements and prevents retired aliases from being reintroduced during future changes.

Retired namespaces currently include public-investment share operations, patent/licensing operations, manual world advancement, dynasty aliases, and the successor alias. Their replacements are civic building operations, corporation research/subscriptions, the trusted scheduler, `/api/house/*`, and `/api/life/successor` respectively.
