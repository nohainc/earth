# AI task template

## Task ID
`[e.g. V5-02A]`

## Target/runtime status
`[current runtime | V5 shadow capability | V5 cutover slice | post-cutover cleanup]`

## Domain
`[capacity | finance | market | governance | corporation | buildings | technology | settlement | read model | Flutter | migration]`

## Slice type
`[new capability | defect fix | refactor | documentation | test | migration | cutover]`

## Goal
`[one bounded user/domain outcome]`

## Read first
- `docs/AI_DEVELOPMENT_INSTRUCTIONS.md`
- `docs/DOCUMENT_STATUS.md`
- For V5 tasks: `docs/v5/README.md`
- For V5 tasks: applicable section of `docs/v5/V5_IMPLEMENTATION_ROADMAP.md`
- `[relevant route/service/engine]`
- `[relevant migration and test]`

## Current-runtime evidence
`[what the repository does today; cite files/tests/schema]`

## Target behavior
`[exact behavior after this slice; do not describe later V5 phases as implemented]`

## Constraints
- PostgreSQL is authoritative.
- Money/resource/capacity authority uses exact integer/numeric semantics.
- Mutations authenticate, authorize, and are idempotent.
- Economic mutations use balanced Economy V2 entries and append-only history.
- Side effects use the outbox pattern.
- Flutter never owns authoritative economic formulas.
- V5 target docs are not evidence of deployed behavior until cutover.

## Schema / migration impact
`[none | forward migration + schema/manifest changes]`

## API / read-model impact
`[routes, DTOs, quote/preview contracts]`

## Settlement impact
`[none | phase/work item/effective-day implications]`

## Flutter impact
`[none | exact screens/components and server-derived data]`

## Idempotency / concurrency
`[correlation key, locking order, replay expectations]`

## Required tests
`[exact focused commands + cases]`

## Manual verification
`[user journey / settlement evidence]`

## Out of scope
`[explicitly deferred items]`

## Definition of done
- [ ] Behaviour and response contract are defined.
- [ ] Migration is append-only when schema changes.
- [ ] Canonical schema/manifest are updated when required.
- [ ] Ledger/history/outbox behavior is covered when authoritative state changes.
- [ ] Focused tests pass.
- [ ] Relevant full quality gates pass.
- [ ] No unrelated files changed.
- [ ] Current vs target implementation status is reported accurately.
- [ ] Commit hash and known deferred work are included in handoff.
