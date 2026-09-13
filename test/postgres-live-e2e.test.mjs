// The live certification entrypoint intentionally reuses the canonical
// PostgreSQL integration tests. Keeping one implementation prevents this
// command from drifting back to deleted legacy schemas or local fixtures.
import './postgres-integration.test.mjs';
import './auth-postgres.test.mjs';
