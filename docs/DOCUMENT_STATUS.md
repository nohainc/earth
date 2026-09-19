# EARTH Documentation Authority

Status: **CURRENT**
Updated: 2026-09-19

This file is the authority map for repository documentation.

## Canonical gameplay authority

EARTH Gameplay **V5 is the only active gameplay design authority**.

Read in this order for gameplay/domain work:

1. `docs/CONSTITUTION.md`
2. `docs/ADR-002-canonical-world-vocabulary.md`
3. `docs/ADR-003-v5-corporation-territory-capacity-model.md`
4. `docs/v5/V5_MASTER_GAMEPLAY_SPEC.md`
5. `docs/v5/V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md`
6. current source, schema, active migrations, and tests for the touched domain

When documentation conflicts with implemented V5 source/schema/tests, repository evidence wins and the conflicting document must be corrected in the same change.

## V5 documents

| Document | Status | Purpose |
| --- | --- | --- |
| `docs/v5/README.md` | CURRENT INDEX | V5 documentation entry point |
| `docs/v5/V5_MASTER_GAMEPLAY_SPEC.md` | CURRENT GAMEPLAY | Canonical player-facing/domain model |
| `docs/v5/V5_PROGRESSIVE_CAPACITY_AND_FISCAL_SPEC.md` | CURRENT GAMEPLAY | Capacity and progressive fiscal semantics |
| `docs/v5/V5_CONSTITUTION_GOVERNANCE_KERNEL.md` | CURRENT IMPLEMENTATION REFERENCE | Constitution/governance implementation notes |
| `docs/v5/V5_DOMAIN_AND_DATA_MIGRATION.md` | IMPLEMENTATION HISTORY / REFERENCE | Migration rationale; not a competing gameplay model |
| `docs/v5/V5_IMPLEMENTATION_ROADMAP.md` | IMPLEMENTATION HISTORY / REFERENCE | Original V5 sequencing; do not treat incomplete phase wording as current runtime status |
| `docs/v5/V5_AI_EXECUTION_PLAYBOOK.md` | EXECUTION GUIDE | V5 task discipline and verification |
| `docs/v5/V5_UI_MIGRATION_MATRIX.md` | CURRENT UX DIRECTION | V5 navigation/page intent; implementation evidence still wins |

## Current engineering and operational references

These remain active when they do not conflict with V5 gameplay authority:

- `docs/AI_DEVELOPMENT_INSTRUCTIONS.md`
- `docs/AI_DEVELOPMENT_GUIDE.md`
- `docs/AI_FILE_MAP.md`
- `docs/ARCHITECTURE.md`
- `docs/ENGINEERING_PLAYBOOK.md`
- `docs/FLUTTER_ARCHITECTURE.md`
- `docs/API_CONTRACT.md`
- `docs/GAME_ECONOMY_SPEC.md`
- `docs/BUILDING_ECONOMY_CONTRACT.md`
- `docs/DATA_AUTHORITY_MATRIX.md`
- `docs/TIME_HANDLING_RULES.md`
- operations/security/deployment documents in `docs/`

## Removed historical gameplay sources

V2/V3/V4 gameplay specifications, status documents, archived city-era designs,
and old redesign plans were removed from the working tree. Git history preserves
them when historical investigation is required.

They must not be copied back into active documentation or used as implementation
authority.

## Vocabulary guardrails

- **EARTH** — global authority.
- **Corporation** — the single local political/economic institution relevant to a House.
- **House** — persistent private player/economic principal.
- **Human** — mortal representative of a House.
- **Community** — voluntary social association, not a government layer.
- **Territory** — standardized physical/geographic capacity context, not a government, tax authority, treasury, or mandatory player-facing management layer.
- **City** — obsolete gameplay/domain term. Do not introduce City entities, APIs, ownership, budgets, services, or navigation in new V5 work.

## Repository-history rule

Do not edit or delete old numbered SQL migrations merely because they mention
retired concepts. Migrations are append-only implementation history. Clean
current schema/source/docs/tests instead, and use a new forward migration when a
database change is required.
