# AI task template

## Domain
`[finance | market | governance | business | read model | Flutter]`

## Slice type
`[new capability | defect fix | refactor | documentation | test]`

## Read first
- `[relevant route/service/engine]`
- `[relevant migration and test]`
- `docs/AI_DEVELOPMENT_INSTRUCTIONS.md`

## Constraints
- PostgreSQL is authoritative; money uses integer cents.
- Mutations authenticate, authorize, and are idempotent.
- Side effects use the outbox pattern.

## Tests to run
`[exact focused command]`

## Definition of done
- [ ] Behaviour and response contract are defined.
- [ ] Migration is append-only when schema changes.
- [ ] Focused tests pass.
- [ ] No unrelated files changed.
