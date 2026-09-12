# EARTH dependency security policy

Runtime dependencies are audited as a release gate with `npm audit --omit=dev --json`.

- Critical and high runtime advisories block CI and deployment.
- Dev-only advisories are assessed separately and do not silently become runtime exceptions.
- An exception requires a reviewed advisory/package identifier in `SECURITY_AUDIT_EXCEPTION_IDS`, a documented reason, an owner, mitigations, and an expiry date.
- Audit-service or report-parsing failures also block the gate; an unavailable advisory service is not treated as a clean result.
- Dependency lockfiles are committed and `npm ci` is used in CI.

The application must not commit secrets, API keys, provider credentials, or production database URLs. Authentication uses secure, HTTP-only, same-site cookies; sensitive actions require the configured MFA check; request bodies are bounded and parsed through the shared validation helper; SQL production calls use parameterized queries and PostgreSQL repositories.
