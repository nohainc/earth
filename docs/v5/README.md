# EARTH Gameplay V5 — Documentation Index

Status: **ACCEPTED TARGET DESIGN / NOT YET CURRENT RUNTIME**  
Audience: product, engineering, AI development agents, reviewers  
Repository: `nohainc/earth`  
Target version: Gameplay V5

## Purpose

This directory is the authoritative planning package for the V5 gameplay migration.
It defines the target gameplay model, the economic/capacity rules, the migration
sequence, and the AI-execution discipline required to move the existing V4 runtime
toward V5 safely.

V5 is a **target architecture until the implementation/cutover gates in this pack
are completed**. AI agents must not describe V5 behavior as implemented merely
because it is specified here.

## Read order for every V5 task

1. `docs/AI_DEVELOPMENT_INSTRUCTIONS.md`
2. `docs/CONSTITUTION.md`
3. `docs/ADR-002-canonical-world-vocabulary.md`
4. `docs/v5/V5_MASTER_GAMEPLAY_SPEC.md`
5. `docs/v5/V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md`
6. `docs/v5/V5_DOMAIN_AND_DATA_MIGRATION.md`
7. `docs/v5/V5_IMPLEMENTATION_ROADMAP.md`
8. The phase/task section in `docs/v5/V5_AI_EXECUTION_PLAYBOOK.md`
9. The relevant current source, migration, tests, and read models

The current Constitution & Governance Kernel implementation is documented in
`V5_CONSTITUTION_GOVERNANCE_KERNEL.md`. It describes the implemented migration
slice and the remaining V5 cutover work.

For UI work also read:

10. `docs/v5/V5_UI_MIGRATION_MATRIX.md`
11. `docs/FLUTTER_ARCHITECTURE.md`

## Document authority

| Document | V5 status | Purpose |
| --- | --- | --- |
| `V5_MASTER_GAMEPLAY_SPEC.md` | TARGET-CANONICAL | Player-facing rules, entity responsibilities, loops, invariants |
| `V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md` | TARGET-CANONICAL | Progressive brackets, Territory capacity, rent, arrears, fiscal flows |
| `V5_DOMAIN_AND_DATA_MIGRATION.md` | TARGET-CANONICAL | Current-to-target domain/schema/API/read-model migration |
| `V5_IMPLEMENTATION_ROADMAP.md` | TARGET-CANONICAL | Ordered phases, dependencies, cutover gates, expected outcomes |
| `V5_AI_EXECUTION_PLAYBOOK.md` | EXECUTION | AI-ready work packages, constraints, tests, handoff requirements |
| `V5_UI_MIGRATION_MATRIX.md` | TARGET-UX | Page-by-page product changes required after authoritative backend slices |

The existing V4 documents remain the authority for **what the current runtime is**
until a V5 phase explicitly replaces that behavior and the corresponding
repository status document is updated.

## Core V5 decision in one paragraph

EARTH UC owns all underlying Territory. A House belongs to at most one active
Corporation. Corporations are the local political/economic institutions and pay
EARTH for the real physical capacity consumed by their members and public assets.
Every House consumes one residential capacity unit plus the footprint of its
private buildings. Territory units are standardized physical capacity containers
that auto-scale from actual occupancy; Houses and buildings are not assigned to a
specific Territory unit while all units are identical. EARTH-to-Corporation and
Corporation-to-House capacity charges use one universal marginal progressive
bracket engine. EARTH governs the global bracket structure and EARTH base land
rate; each Corporation governs its own House base capacity rate. Territory has no
independent government, constitution, tax system, or membership layer.

## Non-negotiable V5 implementation principles

- PostgreSQL remains the only production authority.
- Flutter renders authoritative facts/quotes; it does not reproduce economy rules.
- All money/resource/capacity mutations are atomic, idempotent, and auditable.
- Progressive calculations use exact integer/numeric semantics, never floating point.
- Higher progressive ranges must never have a lower marginal charge than lower ranges.
- Entering a higher bracket never reprices usage already charged in lower brackets.
- One House has at most one active Corporation affiliation.
- Community memberships remain many-to-many and are not Corporation membership.
- Territory is physical capacity, not another government.
- Territory expansion is derived/automatic from occupancy; no routine “found Territory” action exists.
- Every House consumes one protected residential capacity unit.
- Building footprint consumes additional House/Corporation physical capacity.
- A Corporation cannot opt out of EARTH rent while retaining occupied capacity.
- A House cannot opt out of Corporation capacity rent while retaining occupied capacity.
- Non-payment creates arrears and staged resolution; it does not silently erase obligations or instantly delete assets.
- EARTH fiscal underfunding is valid gameplay: programs may be delayed or unavailable when Treasury funds are insufficient.
- V5 migrations must preserve economic history and use forward-only schema changes.

## Definition of V5 cutover

V5 becomes the current gameplay authority only when all of the following are true:

1. The V5 constitutional/domain amendments are accepted in repository docs.
2. Canonical schema and forward migrations support the V5 relationships.
3. Progressive policy and capacity billing are server-authoritative and covered by tests.
4. Daily settlement charges House capacity rent and Corporation EARTH land rent correctly.
5. Corporation admission and founding follow V5 rules.
6. Legacy City/Territory political authority is removed from runtime paths.
7. House/building gameplay no longer depends on a specific Territory unit unless a later explicit V5+ feature reintroduces differentiated geography.
8. V5 read models power the client without client economic fallbacks.
9. Required Flutter migrations are complete for the affected pages.
10. Full automated, migration, replay, invariant, smoke, and monitored game-day gates pass.
11. `docs/DOCUMENT_STATUS.md` and `docs/CURRENT_STATE.md` are updated to mark V5 as current.

Until that cutover, V5 documents describe the target and the V4/runtime documents
describe production behavior.
