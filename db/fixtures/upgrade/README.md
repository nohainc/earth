# PostgreSQL upgrade fixtures

The CI upgrade fixture is produced from the immutable migration history at the
previous release boundary (currently migration 350), then populated with the
canonical seed world. It is intentionally rebuilt from migrations so the
fixture remains reviewable and does not contain production data.

The upgrade certification records counts and accounting totals for houses,
humans, Economy V2, markets, memberships, buildings, research, taxes, budgets,
bank contracts, governance, and outbox data. It applies the current migrations
and asserts that those records and totals survive unchanged.
